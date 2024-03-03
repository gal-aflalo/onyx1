{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "plugins.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "plugins.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "plugins.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create Sisense version from chart version
*/}}
{{- define "plugins.sisense.version" -}}
{{- $sisenseVersion := split "." .Chart.Version -}}
{{- printf "%s.%s.%s" $sisenseVersion._0 $sisenseVersion._1 $sisenseVersion._2 | trimSuffix "." -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "plugins.labels" -}}
release: {{ .Release.Name }}
app: {{ template "plugins.name" . }}
plugins-service: "true"
chart: {{ template "plugins.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
sisense-version: {{ include "plugins.sisense.version" . }}
{{- if .Values.labels -}}
{{- range $key,$value := .Values.labels }}
{{ $key }}: {{ $value }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "plugins.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "plugins.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create template for plugins container.
*/}}
{{- define "plugins.container.command" -}}
# the code below describes the process of managing the plugins during env update process.
# the code of certified plugins is being copied to the plugins service for further usage.
# the marker of clean install/update is presence of readme.md file in the root.
# during clean install it copies the code of certified plugins.
# during env update it checks whether the version of the installed plugin is bigger than the version we get with the update.
# if yes, the env keeps it's version of the plugin. If not, the plugin will be updated.
# the system checks versions from plugin.json files so it's presence is important in every plugin folder.
# the paths to the plugin folders for update is described in the plugin-path.yml file
command:
  - /bin/bash
  - -cx
  - |
    mkdir -p /opt/sisense/storage/plugins;
    mkdir -p /opt/sisense/storage/sdk;
    mkdir -p /usr/src/app/plugins-service;
    ln -s /opt/sisense/storage/plugins /usr/src/app/plugins-service/src;
    ln -s /opt/sisense/storage/sdk /usr/src/app/plugins-service/sdk-api;

    echo "$(date +%Y-%m-%d_%H:%M:%S) : pod init command start" >> /opt/sisense/storage/plugins.log ;

    # compare_semver returns true if first version is newer or equal to second one. otherwise returns false
    # Inline usage example:
    # export version1="1.2.3" && version2="1.2.4" &&  [[ $(compare_semver "$version1" "$version2") = "true" ]] && echo "$version1 is equal or newer than $version2" || echo "$version1 is older than $version2"
    compare_semver() { local IFS=.; local i ver1=($1); local ver2=($2); [[ $1 == $2 ]] && echo true && return; for ((i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++)); do ((ver1[i]=${ver1[i]:-0}, ver2[i]=${ver2[i]:-0})); [[ ${ver1[i]} -gt ${ver2[i]} ]] && echo true && return; [[ ${ver1[i]} -lt ${ver2[i]} ]] && echo false && return; done; echo false; }

    if [ -d /usr/src/app/dist/ ]; then
      cp -fr /usr/src/app/dist/* /usr/src/app/plugins-service/sdk-api/;
    fi;

    if [ ! -f /usr/src/app/plugins-service/src/README.md ]; then
      echo "$(date +%Y-%m-%d_%H:%M:%S) : Readme file not present in /usr/src/app/plugins-service/src/" >> /opt/sisense/storage/plugins.log ;
      cp -fr /usr/src/app/certified-plugins/* /usr/src/app/plugins-service/src/;
    else
       echo "$(date +%Y-%m-%d_%H:%M:%S) : Readme found in /usr/src/app/plugins-service/src/" >> /opt/sisense/storage/plugins.log ;
       echo "$(date +%Y-%m-%d_%H:%M:%S) : Readme file contents: $(cat /usr/src/app/plugins-service/src/README.md)" >> /opt/sisense/storage/plugins.log ;
      mkdir -p /opt/sisense/storage/backups;

      # Use all directory names in plugins directory and separate them by space
      folders_to_backup=$(ls -d /opt/sisense/storage/plugins/*/ | xargs -n1 basename | tr '\n' ' ');

      echo "The next folders will be backed up: $folders_to_backup";
      cd /opt/sisense/storage/plugins;
      tar -zcf /opt/sisense/storage/backups/plugins_backup-last_version-`date +'%y-%m-%d-%H-%M-%S'`.tar.gz `echo $folders_to_backup`;
      cd /opt/sisense/storage/backups && ls -t *plugins* | tail -n +2 | xargs rm -rf;

      rm -f /usr/src/app/certified-plugins/accordionPlugin/config.6.js || true;
      rm -f /usr/src/app/certified-plugins/dynamicElasticubes/config.6.js || true;
      rm -f /usr/src/app/certified-plugins/filteredMeasure/config.js || true;
      rm -f /usr/src/app/certified-plugins/Forecasting/config.6.js || true;
      rm -f /usr/src/app/certified-plugins/jumpToDashboard/js/config.js || true;
      rm -f /usr/src/app/certified-plugins/kmeans/config.js || true;
      rm -f /usr/src/app/certified-plugins/Quest/config.6.js || true;
      rm -f /usr/src/app/certified-plugins/limitSharesAutocomplete/dev/config.6.js || true;
      rm -f /usr/src/app/certified-plugins/SwitchDimension/granularityList.6.js || true;
      # new-line-separated list of plugins

      #force remove BloX add-on as of version L2023.11
       if [ ! -f "/usr/src/app/certified-plugins/BloX" ]; then
            echo "$(date +%Y-%m-%d_%H:%M:%S) : Found BloX add-on in /usr/src/app/certified-plugins/BloX folder. Removing it.
            rm -rf /usr/src/app/certified-plugins/BloX
       fi;
       if [ ! -f "/usr/src/app/plugins-service/src/BloX" ]; then
            echo "$(date +%Y-%m-%d_%H:%M:%S) : Found BloX add-on in /usr/src/app/plugins-service/src/BloX folder. Removing it.
            rm -rf /usr/src/app/plugins-service/src/BloX
       fi;
      #end of force remove BloX add-on

      if [ ! -f "/usr/src/app/certified-plugins/plugin-paths.yml" ]; then
        echo "plugin-paths.yml doesnt exist. Taking list of certified plugins from the hardcoded array";

        echo "$(date +%Y-%m-%d_%H:%M:%S) : plugin-paths.yml doesnt exist. Taking list of certified plugins from the hardcoded array" >> /opt/sisense/storage/plugins.log ;

        plugins_list=("HistogramWidget" "SwitchDimension" "WidgetsTabber" "accordionPlugin" "dynamicBuckets" "dynamicElasticubes" "filteredMeasure" "iFrameWidget" "jaqline" "jumpToDashboard" "limitSharesAutocomplete" "print" "kmeans" "Quest" "office365" );
      else
        plugins_list=$(cat /usr/src/app/certified-plugins/plugin-paths.yml);
      fi;

      for plugin_name in ${plugins_list[@]}; do
        echo -e "\e[32m=== Working on $plugin_name ====\e[39m"
        echo "$(date +%Y-%m-%d_%H:%M:%S) : ==== Working on ${plugin_name} ====" >> /opt/sisense/storage/plugins.log ;

        currentversion=$(cat "/opt/sisense/storage/plugins/${plugin_name}/plugin.json" | grep -w "version" | awk '{print $2}' | tr -d '",');
        fromrelease=$(cat "/usr/src/app/certified-plugins/${plugin_name}/plugin.json" | grep -w "version" | awk '{print $2}' | tr -d '",');
        state=$(cat "/opt/sisense/storage/plugins/${plugin_name}/plugin.json" | grep isEnabled | sed 's/ ,/,/g'| awk '{ print $2 }');
        echo -e "currentversion: $currentversion, fromrelease: $fromrelease";


        echo "$(date +%Y-%m-%d_%H:%M:%S) : isEnabled: ${state}" >> /opt/sisense/storage/plugins.log ;
        echo "$(date +%Y-%m-%d_%H:%M:%S) : currentversion: ${currentversion}, fromrelease: ${fromrelease}" >> /opt/sisense/storage/plugins.log ;


        if [ "$(compare_semver "$currentversion" "$fromrelease" 2>/dev/null)" = "true" ]; then
          echo "Current version is up to date, nothing to copy";
          echo "$(date +%Y-%m-%d_%H:%M:%S) : Current version is up to date, nothing to copy" >> /opt/sisense/storage/plugins.log ;
          rm -rf "/usr/src/app/certified-plugins/${plugin_name}" 2>/dev/null || : ;

          echo "$(date +%Y-%m-%d_%H:%M:%S) : removing /usr/src/app/certified-plugins/${plugin_name}" >> /opt/sisense/storage/plugins.log ;
        else
          echo "Updating the plugin from ${currentversion} to ${fromrelease}";
          echo "$(date +%Y-%m-%d_%H:%M:%S) : Updating the plugin from ${currentversion} to ${fromrelease}" >> /opt/sisense/storage/plugins.log ;

          cp -fr "/usr/src/app/certified-plugins/${plugin_name}" /usr/src/app/plugins-service/src/;
          cd ;
          if [[ $state ]] ; then
            sed -i "s/\"isEnabled\":.*/\"isEnabled\": $state/g" "/usr/src/app/plugins-service/src/${plugin_name}/plugin.json" ;
            echo "$(date +%Y-%m-%d_%H:%M:%S) : isEnabled property updated to '${state}'" >> /opt/sisense/storage/plugins.log ;
            stateVerified=$(cat "/opt/sisense/storage/plugins/${plugin_name}/plugin.json" | grep isEnabled | sed 's/ ,/,/g'| awk '{ print $2 }');
             echo "$(date +%Y-%m-%d_%H:%M:%S) : verifying state got updated. The updated value in /usr/src/app/plugins-service/src/${plugin_name}/plugin.json is: ${stateVerified}" >> /opt/sisense/storage/plugins.log ;
          fi;
          echo "$(date +%Y-%m-%d_%H:%M:%S) : Removing /usr/src/app/certified-plugins/${plugin_name}" >> /opt/sisense/storage/plugins.log ;
          rm -rf "/usr/src/app/certified-plugins/${plugin_name}" 2>/dev/null || : ;
          cd /usr/src/app ;
        fi;

      cd /usr/src/app ;
      done;

      echo "$(date +%Y-%m-%d_%H:%M:%S) : ------ FINISHED UPDATING PLUGINS ------- ">> /opt/sisense/storage/plugins.log ;
      echo "$(date +%Y-%m-%d_%H:%M:%S) : Copying remaining files and folders from /usr/src/app/certified-plugins/ to /usr/src/app/plugins-service/src/ . The remaining files are: $(ls /usr/src/app/certified-plugins | tr '\n' ' ' )" >> /opt/sisense/storage/plugins.log ;

      cp -fr /usr/src/app/certified-plugins/* /usr/src/app/plugins-service/src/ 2>/dev/null || : ;
      content=$(cat /usr/src/app/plugins-service/src/entry.json) ;
      rm -f /usr/src/app/plugins-service/src/entry.json ;
      echo "$content" > /usr/src/app/plugins-service/src/entry.json ;
    fi;
    npm start;
{{- end }}

{{/*
Helper function to determine CPU limit based on conditions
*/}}
{{- define "plugins.limits.cpu" -}}
{{- if (.Values.resources.limits).cpu -}}
{{- .Values.resources.limits.cpu -}}
{{- else if eq "small" (.Values.global.deploymentSize | lower | default "small") -}}
{{- .Values.resources_small.limits.cpu -}}
{{- else if eq "large" (.Values.global.deploymentSize | lower) -}}
{{- .Values.resources_large.limits.cpu -}}
{{- else -}}
{{- .Values.resources_small.limits.cpu -}}
{{- end -}}
{{- end -}}


{{/*
Helper function to determine Memory limit based on conditions
*/}}
{{- define "plugins.limits.memory" -}}
{{- if (.Values.resources.limits).memory -}}
{{- .Values.resources.limits.memory -}}
{{- else if eq "small" (.Values.global.deploymentSize | lower | default "small") -}}
{{- .Values.resources_small.limits.memory -}}
{{- else if eq "large" (.Values.global.deploymentSize | lower) -}}
{{- .Values.resources_large.limits.memory -}}
{{- else -}}
{{- .Values.resources_small.limits.memory -}}
{{- end -}}
{{- end -}}
