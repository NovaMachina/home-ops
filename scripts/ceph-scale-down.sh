#! /bin/bash
for _category in rook-ceph-rgw csi-cephfsplugin-provisioner csi-rbdplugin-provisioner rook-ceph-osd rook-ceph-mon rook-ceph-mgr rook-ceph-exporter rook-ceph-crashcollector; do
    for _item in $(kubectl get deployment -n rook-ceph | awk '/^'"${_category}"'/{print $1}'); do
        kubectl -n rook-ceph scale deployment ${_item} --replicas=0;
        while [[ $(kubectl get deployment -n rook-ceph ${_item} -o jsonpath='{.status.readyReplicas}') != "" ]]; do
            sleep 5;
        done;
    done;
done
