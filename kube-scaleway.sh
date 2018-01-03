#!/bin/bash
set -e

source display.sh
. settings.env

# for id in $(linode_api linode.list | jq ".DATA" | jq -c ".[] | .LINODEID"); do
#   spinner "${CYAN}[$id]${NORMAL} Deleting worker (since certs are now invalid)"\
#               "linode_api linode.delete LinodeID=$id skipChecks=true"
# done
#
# helm install --name traefik --namespace kube-system \
#   --set dashboard.enabled=true,dashboard.auth.basic.kahkhang='$apr1$QRwa3d/1$tU9iLLkuRK4367K4U87OB0',dashboard.domain='traefik.kahkhang.me',acme.enabled=true,acme.email='kahkhang@gmail.com',acme.persistence.enabled=false,loadBalancerIP='45.56.97.29',ssl.enabled=true,ssl.enforced=true \
#   stable/traefik

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

touch settings.env

read_master_plan() {
  IFS=$'\n'
  spinner "Retrieving plans" get_plans plan_data
  local plan_ids=($(echo $plan_data | jq -r '.[] | .PLANID'))
  local plan_list=($(echo $plan_data | jq -r '.[] | [.RAM, .PRICE] | @csv' | \
    awk -v FS="," '{ram=$1/1024; printf "%3sGB (\$%s/mo)%s",ram,$2,ORS}' 2>/dev/null))
  list_input_index "Select a master plan (https://www.linode.com/pricing)" plan_list selected_disk_id
}

get_plans() {
  scw products servers | awk -v FS="," '{ram=$1/1024; printf "%3sGB (\$%s/mo)%s",ram,$2,ORS}'
}
#scw products servers | sed -n 1p
#scw products servers | sed 1,1d | awk '{ if ($2 == "x86_64") { print } }'
#awk '{$1=$1}1' OFS=","

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

get_ip() {
  scw ps -a --no-trunc | grep $1 | grep -E -o '(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)'
}

scw_ssh() {
  ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@"$(get_ip $1)" $2
}

scw_cp() {
  scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $2 core@"$(get_ip $1)":$3
}


spinner "Retrieving available plans" read_available_plans PLANS
tput el
read_master_plan
read_worker_plan
echo $master_plan
echo $master_size
echo $worker_plan
echo $worker_size


#master_id="$(scw create --commercial-type=$master_plan --bootscript=8fd15f37-c176-49a4-9e1d-10eb912942ea --env="boot=live rescue_image=http://j.mp/scaleway-ubuntu-trusty-tarball" $master_size)"
master_id="$(scw create --commercial-type=$master_plan --bootscript=rescue $master_size)"
echo "export master_id=$master_id"
#export master_id=dfc45d07-c9e4-4951-9bf1-73006191037f
scw exec -w "$(scw start $master_id)" "echo started";

[ -e container-linux-config.json ] && rm -rf container-linux-config.json
cat controller-config.json.tmpl | sed "s/\$SSH_KEY/$(cat ~/.ssh/id_rsa.pub | sed 's/\//\\\//g')/g" > container-linux-config.json
while true; do scw cp install-coreos.sh $master_id:/root && break || sleep 10; done
while true; do scw cp container-linux-config.json $master_id:/root && break || sleep 10; done
while true; do scw exec $master_id "chmod +x /root/install-coreos.sh && /root/install-coreos.sh" && break || sleep 5; done
./scw-reboot.expect "$(scw restart $master_id)" "sanboot --no-describe --drive 0x80"
while true; do scw_ssh $master_id "sudo chown -R core:core /home/core" && break || sleep 5; done
scw_ssh $master_id "sudo systemctl start bootkube"
[ -e $DIR/cluster ] && rm -rf $DIR/cluster
mkdir $DIR/cluster
IP="$(get_ip $master_id)"
scp -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r core@${IP}:/home/core/assets/* $DIR/cluster
ssh -i ~/.ssh/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -tt "core@$IP" "rm -rf /home/core/bootstrap.sh"
mkdir -p $HOME/.kube
if [ -e $HOME/.kube/config ]; then
  yes | cp $HOME/.kube/config $HOME/.kube/config.bak
fi
yes | cp $DIR/cluster/auth/kubeconfig $HOME/.kube/config
