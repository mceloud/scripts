#!/bin/bash -xe
export SALT_MASTER_DEPLOY_IP=172.16.164.15
export SALT_MASTER_MINION_ID=cfg01.deploy-name.local
export DEPLOY_NETWORK_GW=172.16.164.1
export DEPLOY_NETWORK_NETMASK=255.255.255.192
export DNS_SERVERS=8.8.8.8

echo "Configuring network interfaces"
envsubst < /root/interfaces > /etc/network/interfaces
ifdown ens3; ifup ens3

echo "Preparing metadata model"
mount /dev/cdrom /mnt/
cp -r /mnt/model/model/* /srv/salt/reclass/
chown -R root:root /srv/salt/reclass/*
chmod -R 644 /srv/salt/reclass/classes/cluster/*
chmod -R 644 /srv/salt/reclass/classes/system/*

echo "updating git repos"
cp -r /mnt/mk-pipelines/* /home/repo/mk/mk-pipelines/
cp -r /mnt/mk-pipelines/.git* /home/repo/mk/mk-pipelines/
cp -r /mnt/pipeline-library/* /home/repo/mcp-ci/pipeline-library/
cp -r /mnt/pipeline-library/.git* /home/repo/mcp-ci/pipeline-library/
chown -R git:www-data /home/repo/mk/mk-pipelines/*
chown -R git:www-data /home/repo/mk/mk-pipelines/.git*
chown -R git:www-data /home/repo/mcp-ci/pipeline-library/*
chown -R git:www-data /home/repo/mcp-ci/pipeline-library/.git*
umount /dev/cdrom

echo "Configuring salt"
#service salt-master restart
envsubst < /root/minion.conf > /etc/salt/minion.d/minion.conf
service salt-minion restart
while true; do
    salt-key | grep "$SALT_MASTER_MINION_ID" && break
    sleep 5
done
sleep 5
for i in `salt-key -l accepted | grep -v Accepted | grep -v "$SALT_MASTER_MINION_ID"`; do
    salt-key -d $i -y
done

find /var/lib/jenkins/jenkins.model.JenkinsLocationConfiguration.xml -type f -print0 | xargs -0 sed -i -e 's/10.167.4.15/'$SALT_MASTER_DEPLOY_IP'/g'

salt-call saltutil.refresh_pillar
salt-call saltutil.sync_all
salt-call state.sls linux.network,linux,openssh,salt
salt-call state.sls maas.cluster,maas.region,reclass

ssh-keyscan cfg01 > /var/lib/jenkins/.ssh/known_hosts

reboot
