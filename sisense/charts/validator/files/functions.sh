#!/usr/bin/env bash

COLOR_OFF='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ROYAL_BLUE='\033[1;36m'

function log_red() {
  local msg=$1
  echo -e "${RED}${msg}${COLOR_OFF}"
}
function log_green() {
  local msg=$1
  echo -e "${GREEN}${msg}${COLOR_OFF}"
}

function log_royal_blue() {
  local msg=$1
  echo -e "${ROYAL_BLUE}${msg}${COLOR_OFF}"
}

function rescue_and_fail(){
    local is_maintenance_running=$(kubectl -n ${NAMESPACE_NAME} get pod | grep -c api-gateway-maintenance)

  if [[ ${is_maintenance_running} -gt 0 ]]; then
    log_red "Scale down maintenance service on upgrade failure"
    kubectl -n "${NAMESPACE_NAME}" scale deployment api-gateway-maintenance --replicas=0
  fi

  log_red "Sisense installation has failed."
  exit 1
}

function get_pods_status() {
  local namespace=$1
  local selector_key=$2
  local selector_value=$3

  kubectl get po -n "${namespace}" --selector="${selector_key}=${selector_value}" --sort-by='.metadata.creationTimestamp' -o jsonpath='{.items[-1].status.phase}' 2> /dev/null
}

function are_all_pods_running() {
  local namespace=$1
  local selector_key=$2
  local selector_value=$3
  local retries=$4
  local desired_state=$5

  for (( attempt=1; attempt<=$retries; attempt++ )); do
    log_royal_blue "Waiting for ${selector_value} pods to be ${desired_state,,} ... Attempt ${attempt}/${retries}"
    pod_statuses=($(get_pods_status "${namespace}" "${selector_key}" "${selector_value}"))
    all_running=true
    if [[ ${#pod_statuses[@]} -eq 0 ]]; then
      all_running=false
    fi
    for status in "${pod_statuses[@]}"; do
      if [[ "${status}" != "${desired_state}" ]]; then
        all_running=false
        break
      fi
    done

    if $all_running; then
      log_green "All pods of ${selector_value} service are ${desired_state,,}"
      return 0
    fi
    sleep 5
  done

  log_red "Pods of ${selector_value} service did not become ${desired_state,,} after ${retries} retries"
  return 1
}

function are_all_pods_ready() {
  local namespace=$1
  local selector_key=$2
  local selector_value=$3
  local retries=$4

  local delay=5
  local timeout="1s"

  for (( attempt=1; attempt<=$retries; attempt++ )); do
    log_royal_blue "Waiting for ${selector_value} pods to be ready ... Attempt ${attempt}/${retries}"
    local is_ready_result=$(kubectl wait --namespace="$namespace" --for=condition=Ready pods --selector="${selector_key}=${selector_value}" --timeout="$timeout" 2>&1)
    if [[ $? -eq 0 ]]; then
      log_green "${selector_value} is ready"
      return 0
    else
      sleep "$delay"
    fi
  done

  log_red "Pods for ${selector_value} did not become ready after ${retries} retries"
  return 1
}

function validate_sisense_pods() {
  local retries=150

  # If "local_mongodb: true", then validate MongoDB is running
  # (In cloud they usually use "Atlas" service, so they don't have MongoDB pod)
  if [[ ${LOCAL_MONGODB,,} == "true" ]]; then
    if ! are_all_pods_running "${NAMESPACE_NAME}" "app.kubernetes.io/name" "mongodb" "$retries" "Running"; then
      rescue_and_fail
    fi
  fi

  items=(
    "zookeeper"
    "rabbitmq"
  )
  # Waiting for pods to be running
  for item in "${items[@]}"; do
    if ! are_all_pods_running "${NAMESPACE_NAME}" "app.kubernetes.io/name" "$item" "$retries" "Running"; then
      rescue_and_fail
    fi
  done

  if ! are_all_pods_running "${NAMESPACE_NAME}" "app" "configuration" "$retries" "Running"; then
    rescue_and_fail
  fi

  echo "Waiting for database migration to complete"
  if ! are_all_pods_running "${NAMESPACE_NAME}" "app.kubernetes.io/name" "migration" "600" "Succeeded"; then
    rescue_and_fail
  fi

  items=(
    "filebrowser"
    "translation"
    "oxygen"
    "model-logspersistence"
    "analyticalengine"
    "usage"
    "jobs"
    "storage"
    "external-plugins"
  )
  # Waiting for pods to be running
  for item in "${items[@]}"; do
    if ! are_all_pods_running "${NAMESPACE_NAME}" "app" "$item" "$retries" "Running"; then
      rescue_and_fail
    fi
  done

  # Waiting for pods to be ready
  for item in "${items[@]}"; do
    selector="app=${item}"
    if ! are_all_pods_ready "${NAMESPACE_NAME}" "app" "$item" "$retries" ; then
      rescue_and_fail
    fi
  done

  # Maintenance | scale down maintenance-service
  local is_maintenance_running=$(kubectl -n ${NAMESPACE_NAME} get pod | grep -c api-gateway-maintenance)

  if [[ ${is_maintenance_running} -gt 0 ]]; then
    echo "Maintenance | scale down maintenance-service"
    kubectl -n "${NAMESPACE_NAME}" scale deployment api-gateway-maintenance --replicas=0
  fi

  echo "Wait for api-gateway pod to become ready"
  if ! are_all_pods_ready "${NAMESPACE_NAME}" "app" "api-gateway" "120"; then
    rescue_and_fail
  fi

  update_system_alias

  # Waiting for internal monitoring
  local is_internal_monitoring=$(kubectl -n ${NAMESPACE_NAME} get cm cm-logmon-${NAMESPACE_NAME}-env -o jsonpath='{.data.internal_monitoring}')
  if [[ ${is_internal_monitoring,,} == "true" ]]; then
    echo "Waiting for internal logging system to run"

    internal_monitoring_items=(
      "fluentd"
      "fluent-bit"
    )
    for item in "${internal_monitoring_items[@]}"; do
      are_all_pods_running "${NAMESPACE_NAME}" "component" "$item" "$retries" "Running"
    done

    monitoring_namespace=$(kubectl -n ${NAMESPACE_NAME} get cm cm-logmon-${NAMESPACE_NAME}-env -o jsonpath='{.data.monitoring_namespace}')
    if [[ -z ${monitoring_namespace} ]]; then
      # In case monitoring_namespace is not showing anywhere, then default hard coded value
      monitoring_namespace=monitoring
    fi

    local is_prometheus_enabled=$(kubectl -n $monitoring_namespace get prometheus --no-headers | wc -l)
    if [[ ${is_prometheus_enabled} -gt 0 ]]; then
      # Waiting for monitoring kube-prometheus-stack pods
      kube_prometheus_stack_items=(
        "alertmanager"
        "prometheus"
        "prometheus-node-exporter"
        "grafana"
      )
      for item in "${kube_prometheus_stack_items[@]}"; do
        are_all_pods_running "${monitoring_namespace}" "app.kubernetes.io/name" "$item" "30" "Running"
      done
      are_all_pods_running "${monitoring_namespace}" "app" "kube-prometheus-stack-operator" "30" "Running"
    fi
  fi

  # Waiting for external monitoring
  local is_external_monitoring=$(kubectl -n ${NAMESPACE_NAME} get cm cm-logmon-${NAMESPACE_NAME}-env -o jsonpath='{.data.external_monitoring}')
  if [[ ${is_external_monitoring,,} == "true" ]]; then 
    echo "Waiting for external logging system to run"

    external_monitoring_items=(
      "fluentd"
    )
    for item in "${external_monitoring_items[@]}"; do
      are_all_pods_running "${monitoring_namespace}" "k8s-app" "$item" "$retries" "Running"
    done
  fi

  # Restart configuration deployment and wait
  if [[ ${IS_UPGRADE,,} == "true" ]]; then
    echo "Restart configuration deployment"
    kubectl -n "${NAMESPACE_NAME}" rollout restart deployment configuration

    echo "Wait for configuration deployment to be ready"
    if ! are_all_pods_running "${NAMESPACE_NAME}" "app" "configuration" "$retries" "Running"; then
      rescue_and_fail
    fi
  fi
}

function print_adress_or_load_balancer(){
  load_balancer_address=''

  if [[ ${CLUSTER_VISIBILITY,,} == "true" ]]; then

    cloud_provider=$(kubectl get no -o jsonpath='{.items[0].spec.providerID}')

    if [[ ${cloud_provider} == *"aws"* && ${ALB_CONTROLLER,,} == true ]]; then
      tmp=$(kubectl get ing sisense-ingress -n "${NAMESPACE_NAME}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
      if [[ -n $tmp ]]; then
        load_balancer_address=$tmp

        current_alias=$(kubectl -n ${NAMESPACE_NAME} get cm global-configuration -ojsonpath='{.data.SYSTEM_ALIAS}')
        local alb_protocol=http
        if kubectl get ing sisense-ingress -n "${NAMESPACE_NAME}" -o yaml | grep -q alb.ingress.kubernetes.io/certificate-arn; then
          alb_protocol=https
        fi
        if [[ "${current_alias}" != "${alb_protocol}://${load_balancer_address}" ]]; then
          echo "Updateing the SYSTEM_ALIAS with ALB address and restarting relevant pods"
          kubectl -n ${NAMESPACE_NAME} patch cm global-configuration -p "{\"data\": {\"SYSTEM_ALIAS\": \"${alb_protocol}://${load_balancer_address}\"}}"
          export ALIAS_UPDATED=true
          update_system_alias
        fi
      fi
    fi

    if [[ (( ${IS_SSL,,} == "true" ) || (${IS_SSL,,} != "true" && ${GATEWAY_PORT} -eq 80)) && (-z ${ALB_CONTROLLER} || ${ALB_CONTROLLER,,} == false) ]]; then
      svc_namespace=$(kubectl get svc -A | grep nginx-ingress-ingress-nginx-controller | awk '{print $1}')
      if [[ -n $svc_namespace ]]; then
        tmp=$(kubectl get svc nginx-ingress-ingress-nginx-controller -n "${svc_namespace}" -o jsonpath="{.status.loadBalancer.ingress[*].*}")
        if [[ -n $tmp ]]; then
          load_balancer_address=$tmp
        fi
      fi
    fi

    if [[ (${IS_SSL,,} != "true" && ${GATEWAY_PORT} -ne 80) && (-z ${ALB_CONTROLLER} || ${ALB_CONTROLLER,,} == false) ]]; then
      tmp=$(kubectl get svc api-gateway-external -n "${NAMESPACE_NAME}" -o jsonpath="{.status.loadBalancer.ingress[*].*}")
      if [[ -n $tmp ]]; then
        load_balancer_address=$tmp
        
        current_alias=$(kubectl -n ${NAMESPACE_NAME} get cm global-configuration -ojsonpath='{.data.SYSTEM_ALIAS}')
        if [[ "${current_alias}" != "http://${load_balancer_address}" ]]; then
          echo "Updateing the SYSTEM_ALIAS with LB address and restarting relevant pods"
          kubectl -n ${NAMESPACE_NAME} patch cm global-configuration -p "{\"data\": {\"SYSTEM_ALIAS\": \"http://${load_balancer_address}\"}}"
          export ALIAS_UPDATED=true
          update_system_alias
        fi
      fi
    fi

    log_green "\nSisense intallation process completed successfuly."
    if [[ -n $load_balancer_address ]];then
      log_green "The app is accessible on address: ${load_balancer_address}"
    else
      # It already gets the ${base_proto}${print_ip}${print_port} from function print_endpoint
      log_green "The app is accessible on address: ${base_proto}${print_ip}${print_port} "
    fi

  else

    if [[ (${IS_SSL,,} != "true" && ${GATEWAY_PORT} -ne 80) && (-z ${ALB_CONTROLLER} || ${ALB_CONTROLLER,,} == false) ]]; then
      tmp=$(kubectl get svc api-gateway-external -n "${NAMESPACE_NAME}" -o jsonpath="{.status.loadBalancer.ingress[*].*}")
      if [[ -n $tmp ]]; then
        load_balancer_address=$tmp
      fi
    fi

    log_green "\nSisense intallation process completed successfuly."
    if [[ -n $load_balancer_address ]];then
      log_green "The app is accessible on address: ${load_balancer_address}"
    else
      # It already gets the ${base_proto}${print_ip}${print_port} from function print_endpoint
      log_green "The app is accessible on address: ${base_proto}${print_ip}${print_port} "
      log_green "\nCluster visibility is disabled. To obtain the Load Balancer address, if exists, please follow these steps:"

      echo "For AWS cloud provider with ALB controller:"
      echo "- Run the following command:"
      echo "  kubectl get ing sisense-ingress -n "${NAMESPACE_NAME}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"

      echo "For SSL or Non-SSL with Port 80:"
      echo "- Run the following command:"
      echo "  kubectl get svc nginx-ingress-ingress-nginx-controller -n \"${UTILS_NAMESPACE}\" -o jsonpath='{.status.loadBalancer.ingress[*].*}'"
    fi
  fi
}

function update_system_alias() {
  echo "OLD_SYSTEM_ALIAS = ${OLD_SYSTEM_ALIAS}" 
  echo "SYSTEM_ALIAS = ${SYSTEM_ALIAS}"
  echo "ALIAS_UPDATED = ${ALIAS_UPDATED}"
  
  # If customer changed the application_dns_name
  if [[ (${IS_UPGRADE,,} == "true" && -n ${OLD_SYSTEM_ALIAS} && ${OLD_SYSTEM_ALIAS} != ${SYSTEM_ALIAS}) || (${ALIAS_UPDATED,,} == "true") ]]; then
    echo "System alias changed, restarting relevant deployments"
    
    local retries=150
    local deployments="analyticalengine api-gateway configuration galaxy identity usage pivot2-be quest"
    kubectl -n ${NAMESPACE_NAME} rollout restart deploy ${deployments}

    items=(
      "analyticalengine"
      "api-gateway"
      "configuration"
      "usage"
      "pivot2-be"
      "quest"
    )

    # "galaxy" "identity" won't be Running in first installation until activation is done
    if [[ ${IS_UPGRADE,,} == "true" ]]; then items+=("galaxy" "identity"); fi

    # Waiting for pods to be running
    for item in "${items[@]}"; do
      if ! are_all_pods_running "${NAMESPACE_NAME}" "app" "$item" "$retries" "Running"; then
        rescue_and_fail
      fi
    done

    # Waiting for pods to be ready
    for item in "${items[@]}"; do
      selector="app=${item}"
      if ! are_all_pods_ready "${NAMESPACE_NAME}" "app" "$item" "$retries" ; then
        rescue_and_fail
      fi
    done

  fi
}

function print_endpoint(){
  base_proto=''
  print_ip=''
  print_port=''

  if [[ ${IS_SSL,,} == "true" ]]; then
    base_proto='https://'
  else
    base_proto='http://'
  fi

  is_address_contains_proto=false

  if [[ -n ${APPLICATION_DNS_NAME} || -n ${SYSTEM_ALIAS} ]]; then

    # Take APPLICATION_DNS_NAME first, but if not existing then take SYSTEM_ALIAS
    print_ip=${APPLICATION_DNS_NAME:-${SYSTEM_ALIAS}}
    if [[ ${print_ip} == *"http"* ]]; then
      base_proto=''
      is_address_contains_proto=true
    fi

  #else
    #external_ip=$(kubectl get cm -n "${NAMESPACE_NAME}" "prov-${NAMESPACE_NAME}-provisioner" -ojsonpath='{.data.prov-values\.yml}' | grep -A 5 'k8s_nodes:' | grep -o 'external_ip: .*' | awk -F ": " '{print $2}' | head -n 1)
    #if [ -n "$external_ip" ] && [ "$external_ip" != "0.0.0.0" ]; then
    #  print_ip=$external_ip
    #fi
  fi

  if [[ -z ${print_ip} && ${CLUSTER_VISIBILITY,,} == "true" ]]; then
    #first_node=$(kubectl get cm -n sisense prov-${NAMESPACE_NAME}-provisioner -ojsonpath='{.data.prov-values\.yml}' | grep -A 5 'k8s_nodes:' | grep -o 'node: .*' | awk -F ": " '{print $2}' | head -n 1)
    print_ip=$(kubectl get node -o jsonpath='{.items[0].status.addresses[0].address}')
  fi

  if [[ ( ${IS_SSL,,} != "true") && ( ${CLOUD_LOAD_BALANCER,,} != "true" ) && ( ( -z ${APPLICATION_DNS_NAME} && -z ${SYSTEM_ALIAS} ) || ${is_address_contains_proto} == "false" ) ]]; then
    print_port=":${GATEWAY_PORT}"
  fi

  print_adress_or_load_balancer
  if [[ ${EXPOSE_NODEPORTS,,} != "true" ]]; then
    echo -e "
    In order to access Sisense CLI and Completion file, you can execute:
    $ kubectl get cm --namespace ${NAMESPACE_NAME} add-completion -ojsonpath='{.data.*}' > add_completion-${NAMESPACE_NAME}.sh
    $ source add_completion-${NAMESPACE_NAME}.sh\n"
  else
    log_green "\nManagement Swagger UI at ${base_proto}${print_ip%:*}:30082/swagger-ui.html "
    log_green "Query Swagger UI at ${base_proto}${print_ip%:*}:30084/swagger-ui.html "
    log_green "Build Swagger UI at ${base_proto}${print_ip%:*}:30086/swagger-ui.html "
    log_green "App Test UI at ${base_proto}${print_ip}${print_port}/app/test \n"
  fi
}
