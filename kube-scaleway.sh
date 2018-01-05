#!/bin/bash

source display.sh

datacenter_list=('Paris' 'Amsterdam')
list_input "Select a datacenter" datacenter_list selected_datacenter
if [ $selected_datacenter = "Paris" ]; then
  datacenter="par1"
else
  datacenter="ams1"
fi

read_available_plans() {
  #TODO: some monthly price plans are null (hardcode or open a ticket)
  PLANS="$(curl -s https://cp-$datacenter.scaleway.com/products/servers | jq -r '.servers')"
  AVAILABILITY="$(curl -s https://cp-$datacenter.scaleway.com/products/servers/availability | jq -r '.servers')"
  echo "$PLANS" "$AVAILABILITY" | \
    jq -s 'reduce .[] as $item ({}; . * $item)' | \
    jq -r 'to_entries[]
      | select(.value | .arch=="x86_64")
      | select(.value | .monthly_price > 0)
      | select(.value | .availability!="shortage")' | \
    jq -r '{"id" : .key,
       "price" : ("€" + (.value.monthly_price|tostring)),
       "size" : ((if .value.volumes_constraint.max_size > 0 then
          .value.volumes_constraint.max_size/(1000*1000*1000) else
          50
       end|tostring) + "GB"),
       "ram" : ((.value.ram/(1024*1024*1024)|tostring) + "GB"),
       "availability" : .value.availability}'
}

read_no_of_workers() {
  if ! [[ $NO_OF_WORKERS =~ ^[0-9]+$ ]] 2>/dev/null; then
      while ! [[ $NO_OF_WORKERS =~ ^[0-9]+$ ]] 2>/dev/null; do
         text_input "Enter number of workers: " NO_OF_WORKERS "^[0-9]+$" "Please enter a number"
      done
  fi
}

read_master_plan() {
  IFS=$'\n'
  plan_list=($(echo "$PLANS" | jq -r '[.ram, .size, .price] | join(",")' | \
    awk -v FS="," '{printf "%3s RAM, %5s disk (%s/mo)%s",$1,$2,$3,ORS}' 2>/dev/null))
  list_input_index "Select a plan for the master node" plan_list plan_id
  plan_ids=($(echo "$PLANS" | jq -r '.id'))
  sizes=($(echo "$PLANS" | jq -r '.size'))
  master_plan="${plan_ids[$plan_id]}"
  master_size="${sizes[$plan_id]}"
}

read_worker_plan() {
  IFS=$'\n'
  plan_list=($(echo "$PLANS" | jq -r '[.ram, .size, .price] | join(",")' | \
    awk -v FS="," '{printf "%3s RAM, %5s disk (%s/mo)%s",$1,$2,$3,ORS}' 2>/dev/null))
  list_input_index "Select a plan for the worker nodes" plan_list plan_id
  plan_ids=($(echo "$PLANS" | jq -r '.id'))
  sizes=($(echo "$PLANS" | jq -r '.size'))
  worker_plan="${plan_ids[$plan_id]}"
  worker_size="${sizes[$plan_id]}"
}

read_domain() {
  domain_regex="^([a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.)+[a-zA-Z]{2,}$"
  if ! [[ $DOMAIN =~ $domain_regex ]] 2>/dev/null; then
      while ! [[ $DOMAIN =~ $domain_regex ]] 2>/dev/null; do
         text_input "Enter Domain Name: " DOMAIN "$domain_regex" "Please enter a valid domain name"
      done
  fi
  tput civis
}

read_email() {
  email_regex="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
  if ! [[ $EMAIL =~ $email_regex ]] 2>/dev/null; then
      while ! [[ $EMAIL =~ $email_regex ]] 2>/dev/null; do
         text_input "Enter Email: " EMAIL "^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$" "Please enter a valid email"
      done
  fi
  tput civis
}

read_username() {
  if [ -z "$USERNAME" ]; then
    [ -e auth ] && rm auth
    [ -e manifests/grafana/grafana-credentials.yaml ] && rm manifests/grafana/grafana-credentials.yaml
    text_input "Enter dashboard username: " USERNAME
  fi
  tput civis
}

read_password() {
  read -s -p "Enter your dashboard password: " PASSWORD
  tput cub "$(tput cols)"
  tput el
}

get_ip() {
  scw ps -a --no-trunc | grep $1 | grep -E -o '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)'
}

get_private_ip() {
  scw inspect $1 | jq '.[0].private_ip' | sed 's/"//g'
}

get_id() {
  scw ps -a --no-trunc | grep $1 | grep -E -o '^([0-9a-z]-?)+'
}

provision_master() {
  local ID
  local IP
  ID=$(get_id master)
  if ! [[ $ID =~ ^([0-9a-z]-?)+$ ]] 2>/dev/null; then
    ID="$(scw create --name=master --commercial-type=$master_plan --bootscript=rescue $master_size)"
    scw exec -w "$(scw start $ID)" "echo started";
  else
    scw restart $ID
    scw exec -w "$ID" "echo started";
  fi
  echo "export ID=$ID"
  echo "export IP=$(get_ip $ID)"
  set -e
  IP="$(get_ip $ID)"
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r install-coreos.sh root@${IP}:~/install-coreos.sh
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r manifests/container-linux/controller-config.yaml root@${IP}:~/container-linux-config.yaml
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${IP} "chmod +x ./install-coreos.sh && ./install-coreos.sh"
  ./scw-reboot.expect "$(scw restart $ID)" "sanboot --no-describe --drive 0x80"
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${IP} "sudo chown -R core:core /home/core"
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${IP} "sudo systemctl start bootkube"
  [ -e cluster ] && rm -rf cluster
  mkdir cluster
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${IP} "sudo chown -R core:core /opt/bootkube/assets"
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r core@${IP}:/opt/bootkube/assets/* cluster
  mkdir -p ~/.kube
  [ -e ~/.kube/config.bak ] && rm ~/.kube/config.bak
  [ -e ~/.kube/config ] && mv ~/.kube/config ~/.kube/config.bak
  cp cluster/auth/kubeconfig ~/.kube/config
  set +e
}

provision_worker() {
  local ID
  local IP
  ID=$(get_id worker-$1)
  if ! [[ $ID =~ ^([0-9a-z]-?)+$ ]] 2>/dev/null; then
    ID="$(scw create --name=worker-$1 --commercial-type=$worker_plan --bootscript=rescue $worker_size)"
    scw exec -w "$(scw start $ID)" "echo started";
  else
    scw restart $ID
    scw exec -w "$ID" "echo started";
  fi
  echo "export ID=$ID"
  echo "export IP=$(get_ip $ID)"

  set -e
  IP="$(get_ip $ID)"
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r install-coreos.sh root@${IP}:~/install-coreos.sh
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r manifests/container-linux/worker-config.yaml root@${IP}:~/container-linux-config.yaml
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${IP} "chmod +x ./install-coreos.sh && ./install-coreos.sh"
  ./scw-reboot.expect "$(scw restart $ID)" "sanboot --no-describe --drive 0x80"
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${IP} "sudo chown -R core:core /home/core"
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no cluster/auth/kubeconfig core@${IP}:/home/core/kubeconfig
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@${IP} "sudo ./bootstrap.sh"
  set +e
}

spinner "Retrieving available plans" read_available_plans PLANS
tput el
read_master_plan
read_worker_plan
read_no_of_workers
read_domain
read_email
read_username
read_password

set +e

provision_master

for NO in $( seq $NO_OF_NEW_WORKERS ); do
  provision_worker $NO
done


[ -e auth ] && rm auth
htpasswd -b -c auth $USERNAME $PASSWORD >/dev/null 2>&1
[ -e manifests/grafana/grafana-credentials.yaml ] && rm manifests/grafana/grafana-credentials.yaml
cat > manifests/grafana/grafana-credentials.yaml <<-EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-credentials
data:
  user: $( echo -n $USERNAME | base64 $base64_args )
  password: $( echo -n $PASSWORD | base64 $base64_args )
EOF

while true; do kubectl --namespace=kube-system create secret generic kubesecret --from-file auth --request-timeout 0 && break || sleep 5; done
if kubectl --request-timeout 0 get namespaces | grep -q "monitoring"; then
  echo "namespace monitoring exists"
else
  while true; do kubectl create namespace "monitoring" --request-timeout 0 && break || sleep 5; done
fi
if kubectl --request-timeout 0 get namespaces | grep -q "rook"; then
  echo "namespace rook exists"
else
  while true; do kubectl create namespace "rook" --request-timeout 0 && break || sleep 5; done
fi
while true; do kubectl --namespace=monitoring create secret generic kubesecret --from-file auth --request-timeout 0 && break || sleep 5; done
while true; do kubectl apply -f manifests/heapster.yaml --validate=false --request-timeout 0 && break || sleep 5; done

# Install K8S dashboard
while true; do cat manifests/kube-dashboard.yaml | sed "s/\${DOMAIN}/${DOMAIN}/g" | kubectl apply --request-timeout 0 --validate=false -f - && break || sleep 5; done

# Install Traefik
while true; do cat manifests/traefik.yaml | sed "s/\${DOMAIN}/${DOMAIN}/g" | sed "s/\${MASTER_IP}/${IP}/g" | sed "s/\$EMAIL/${EMAIL}/g" | kubectl apply --request-timeout 0 --validate=false -f - && break || sleep 5; done

# Install Rook
while true; do kubectl apply -f manifests/rook/rook-operator.yaml --request-timeout 0 && break || sleep 5; done
while true; do kubectl apply -f manifests/rook/rook-cluster.yaml --request-timeout 0 && break || sleep 5; done
while true; do kubectl apply -f manifests/rook/rook-storageclass.yaml --request-timeout 0 && break || sleep 5; done

# Install Prometheus
while true; do kubectl --namespace monitoring apply -f manifests/prometheus-operator --request-timeout 0 && break || sleep 5; done
printf "Waiting for Operator to register third party objects..."
until kubectl --namespace monitoring get servicemonitor > /dev/null 2>&1; do sleep 1; printf "."; done
until kubectl --namespace monitoring get prometheus > /dev/null 2>&1; do sleep 1; printf "."; done
until kubectl --namespace monitoring get alertmanager > /dev/null 2>&1; do sleep 1; printf "."; done
while true; do kubectl --namespace monitoring apply -f manifests/node-exporter --request-timeout 0 && break || sleep 5; done
while true; do kubectl --namespace monitoring apply -f manifests/kube-state-metrics --request-timeout 0 && break || sleep 5; done
while true; do kubectl --namespace monitoring apply -f manifests/grafana/grafana-credentials.yaml --request-timeout 0 && break || sleep 5; done
while true; do kubectl --namespace monitoring apply -f manifests/grafana --request-timeout 0 && break || sleep 5; done
while true; do find manifests/prometheus -type f ! -name prometheus-k8s-roles.yaml ! -name prometheus-k8s-role-bindings.yaml ! -name prometheus-k8s-ingress.yaml -exec kubectl --request-timeout 0 --namespace "monitoring" apply -f {} \; && break || sleep 5; done
while true; do kubectl apply -f manifests/prometheus/prometheus-k8s-roles.yaml --request-timeout 0 && break || sleep 5; done
while true; do kubectl apply -f manifests/prometheus/prometheus-k8s-role-bindings.yaml --request-timeout 0 && break || sleep 5; done
while true; do kubectl --namespace monitoring apply -f manifests/alertmanager/ --request-timeout 0 && break || sleep 5; done
while true; do cat manifests/prometheus/prometheus-k8s-ingress.yaml | sed "s/\${DOMAIN}/${DOMAIN}/g" | kubectl apply --request-timeout 0 --validate=false -f - && break || sleep 5; done
