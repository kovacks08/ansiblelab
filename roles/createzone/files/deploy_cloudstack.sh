#!/bin/bash

# Specify connection data

#cloudmonkey_config=/root/.cloudmonkey/config.lab10.cpman2
#config_file=zone.cfg

while getopts c:z: opt; do
  case $opt in
  c)
    cloudmonkey_config=$OPTARG
	echo $cloudmonkey_config
    ;;
  z)
    config_file=$OPTARG
	echo $config_file
    ;;
  esac
done



if [ -r $cloudmonkey_config ]; then
	echo "cloudmonkey config file $config_file"
	cli="cloudmonkey -c $cloudmonkey_config"
else
	echo "Please specify correct cloudmonkey config file"
	exit 100
fi



# Read configuration file


if [ -r $config_file ]; then
	echo "Reading config file $config_file"
	source "$config_file"
else
	echo "Please create config file $config+file"
	exit 100
fi

echo $cloudmonkey_config
echo $config_file

echo "Deploying data for zone: $zone_name"
echo "____________________________________________________________"

### Zone id creation ###

$cli set display default

zone_id=`$cli create zone dns1=$dns_ext1 dns2=$dns_ext2 internaldns1=$dns_int1 internaldns2=$dns_int2 name=$zone_name networktype=Advanced guestcidraddress=$guest_cidr domain=$guest_domain securitygroupenabled=false | grep ^id\ = | awk '{print $3}'`
if [[ $? != 0 ]]
then	
	exit 2
else
	echo "Created zone" $zone_id
fi

### physical networks creation ###
### Assuming 2 networks with VLAN isolation method ###

phynet1_id=`$cli create physicalnetwork name=$phynet1_name zoneid=$zone_id isolationmethods=VLAN | grep ^id\ = | awk '{print $3}'`
if [[ $? != 0 ]]; then
	echo " Error creating physical network1"
        exit 3
else
	echo "Created physical network1" $phy_id
fi

phynet2_id=`$cli create physicalnetwork name=$phynet2_name zoneid=$zone_id isolationmethods=VLAN | grep ^id\ = | awk '{print $3}'`
if [[ $? != 0 ]]; then
	echo " Error creating physical network2"
        exit 4
else
	echo "Created physical network2" $phy_id
fi


### Create the networks traffics on top of the physical networks created ####
### vmwarenetwork labels are created with comma separated values
### Public and guest traffic types
### <Virtual Switch Name>,<VLAN>,<VMware switch type: vmwaresvs or vmwaredvs>
### Storage and Management traffic types
### <Virtual Switch Name>,<VLAN>
### Networks on top of physical network 1 ###


### Management network creation ###
#$cli add traffictype traffictype=Management physicalnetworkid=${mgmt_traffic_phynet}_id vmwarenetworklabel="${mgmt_traffic_vswitch},${mgmt_traffic_vlan},${mgmt_traffic_vswitch_type}"
$cli add traffictype traffictype=Management physicalnetworkid=$phynet1_id vmwarenetworklabel="${mgmt_traffic_vswitch},${mgmt_traffic_vlan},${mgmt_traffic_vswitch_type}"
if [[ $? != 0 ]]; then
        echo "Error adding mgmt traffic"
        exit 10
else
        echo "Added mgmt traffic"
fi

### Public network creation ###
$cli add traffictype traffictype=Public physicalnetworkid=$phynet1_id vmwarenetworklabel="${public_traffic_vswitch},${public_traffic_vlan},${public_traffic_vswitch_type}"
if [[ $? != 0 ]]; then
        echo "Error adding public traffic"
        exit 11
else
        echo "Added public traffic"
fi


### Guest traffic type
$cli add traffictype traffictype=Guest physicalnetworkid=$phynet1_id vmwarenetworklabel="${guest_traffic_vswitch},${guest_traffic_vlan},${guest_traffic_vswitch_type}"
if [[ $? != 0 ]]; then
        echo "Error adding guest traffic"
        exit 12
else
        echo "Added guest traffic"
fi


### Storage network creation ###
#$cli add traffictype traffictype=Storage physicalnetworkid=${storage_traffic_phynet}_id vmwarenetworklabel="${storage_traffic_vswitch},${storage_traffic_vlan},${storage_traffic_vswitch_type}"
$cli add traffictype traffictype=Storage physicalnetworkid=$phynet2_id vmwarenetworklabel="${storage_traffic_vswitch},${storage_traffic_vlan},${mgmt_traffic_vswitch_type}"
if [[ $? != 0 ]]; then
        echo "Error adding storage traffic"
        exit 13
else
        echo "Added storage traffic"
fi



### Enable the actual physical networks ###
$cli update physicalnetwork state=Enabled id=$phynet1_id
if [[ $? != 0 ]]; then
	echo "Error enabling physical network 1"
        exit 14
else
	echo "Enabled physicalnetwork 1" $phynet1_id
fi

$cli update physicalnetwork state=Enabled id=$phynet2_id
if [[ $? != 0 ]]; then
        echo "Error enabling physical network 2"
        exit 15
else
        echo "Enabled physicalnetwork 2" $phynet1_id
fi


### Configure Network Service Providers
### Not focusing on that part for the time being
echo "------------------------- Network services configuration  -------------------------"

for phynet_id in $phynet1_id $phynet2_id;
do
  guest_nsp_id=`$cli list networkserviceproviders name=VirtualRouter physicalNetworkId=$phynet_id filter=id  | grep ^id\ = | awk '{print $3}'`
  echo "Enabled vr networkserviceprovider" $guest_nsp_id

  vpc_nsp_id=`$cli list networkserviceproviders name=VPCVirtualRouter physicalNetworkId=$phynet_id filter=id | grep ^id\ = | awk '{print $3}'`
  echo "Enabled vpc vr networkserviceprovider" $vpc_nsp_id

  for nsp_id in $guest_nsp_id $vpc_nsp_id;
  do
    echo "configure nsp" $nsp_id

    vrelem_id=`$cli list virtualrouterelements nspid=$nsp_id filter=id  | grep ^id\ = | awk '{print $3}'`

    $cli configure virtualrouterelement id=$vrelem_id enabled=true
    echo "configured virtualrouterelement" $vrelem_id


  done;

  $cli update networkserviceprovider id=$guest_nsp_id state=Enabled

  $cli update networkserviceprovider id=$vpc_nsp_id state=Enabled


  internal_lb_nsp_id=`$cli list networkserviceproviders name=InternalLbVm physicalNetworkId=$phynet_id filter=id  | grep ^id\ = | awk '{print $3}'`
  echo "Enabled internal lb networkserviceprovider" $internal_lb_nsp_id

  internal_lb_elem_id=`$cli list internalloadbalancerelements nspid=$internal_lb_nsp_id filter=id  | grep ^id\ = | awk '{print $3}'`
  $cli configure internalloadbalancerelement id=$internal_lb_elem_id enabled=true
  echo "configured internalloadbalancerelement" $internal_lb_elem_id

  $cli update networkserviceprovider id=$internal_lb_nsp_id state=Enabled

done;


### POD Configuration ###

echo "------------------------- POD configuration -------------------------"

pod_id=`$cli create pod name=$pod_name zoneid=$zone_id gateway=$system_gw netmask=$system_nmask startip=$pod_ip_start endip=$pod_ip_end | grep ^id\ = | awk '{print $3}'`
echo "Created pod" $pod_id

### Create the public IP range

$cli create vlaniprange zoneid=$zone_id gateway=$public_gw netmask=$public_nmask startip=$public_ip_start endip=$public_ip_end forvirtualnetwork=true vlan=$public_vlan
echo "Created Public IP range"

### Create the storage IP range
$cli create storagenetworkiprange podid=$pod_id gateway=$storage_gw netmask=$storage_nmask startip=$storage_ip_start endip=$storage_ip_end vlan=$storage_vlan
echo "Created Storage Network range"

### Add the vlan range to the physical network
$cli update physicalnetwork id=$phynet1_id vlan=${guest_vlan_range}
echo "Added guests vlan range"



echo "------------------------- VMware configuration -------------------------"
### Create the actual VMware cluster

vmware_dc_id=`$cli add vmwaredc name=$vmware_dc password=$vmware_password username=$vmware_user vcenter=$vmware_host zoneid=$zone_id | grep ^id\ = | awk '{print $3}'`

vmware_cluster_id1=`$cli add cluster zoneid=$zone_id hypervisor=$hypervisor clustertype=ExternalManaged username=$vmware_user password=$vmware_password podid=$pod_id url=http://${vmware_host}/${vmware_dc}/${vmware_cluster1} clustername=${vmware_host}/${vmware_dc}/${vmware_cluster1} | grep ^id\ = | awk '{print $3}'`
echo "Created cluster $vmware_cluster_id1"

### If cluster2 and/or cluster 3 are defined we create those clusters too
if [[ -n $vmware_cluster2 ]]; then
    vmware_cluster_id2=`$cli add cluster zoneid=$zone_id hypervisor=$hypervisor clustertype=ExternalManaged username=$vmware_user password=$vmware_password podid=$pod_id url=http://${vmware_host}/${vmware_dc}/${vmware_cluster2} clustername=${vmware_host}/${vmware_dc}/${vmware_cluster2} | grep ^id\ = | awk '{print $3}'`
    echo "Created cluster $vmware_cluster_id2"
fi

if [[ -n $vmware_cluster3 ]]; then 
    vmware_cluster_id3=`$cli add cluster zoneid=$zone_id hypervisor=$hypervisor clustertype=ExternalManaged username=$vmware_user password=$vmware_password podid=$pod_id url=http://${vmware_host}/${vmware_dc}/${vmware_cluster3} clustername=${vmware_host}/${vmware_dc}/${vmware_cluster3} | grep ^id\ = | awk '{print $3}'`
    echo "Created cluster $vmware_cluster_id3"
fi

### Create primary Storage
primary_storage_id=`$cli create storagepool scope=zone zoneid=$zone_id hypervisor=$hypervisor name=$primary_storage_name zoneid=$zone_id podid=$pod_id scope=$primary_storage_scope tags=$primary_storage_tags url=${primary_storage_protocol}://${primary_storage_server}:${primary_storage_path} | grep ^id\ = | awk '{print $3}'`
echo "Added primary storage $primary_storage_id"

### Create EBS Storage
ebs_storage_id=`$cli create storagepool scope=zone zoneid=$zone_id hypervisor=$hypervisor name=$ebs_storage_name zoneid=$zone_id podid=$pod_id scope=$ebs_storage_scope tags=$ebs_storage_tags url=${ebs_storage_protocol}://${ebs_storage_server}:${ebs_storage_path} | grep ^id\ = | awk '{print $3}'`
echo "Added EBS storage $ebs_storage_id"

### Create Secondary Storage
secondary_storage_id=`$cli add imagestore zoneid=$zone_id name=$secondary_storage_name provider=$secondary_storage_provider url=${secondary_storage_provider}://${secondary_storage_server}${secondary_storage_path} | grep ^id\ = | awk '{print $3}'      `
echo "Added secondary storage $secondary_storage_id"

echo "Advanced zone deployment completed!"
echo "------------------------- Enable zone -------------------------"
$cli update zone allocationstate=Enabled id=$zone_id
