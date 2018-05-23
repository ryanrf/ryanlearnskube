#!/bin/bash
create_kubelet_clusterrole(){
printf 'apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
' | kubectl apply --kubeconfig admin.kubeconfig -f -
}

kubelet_clusterrolebinding(){
printf 'apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
' | kubectl apply --kubeconfig admin.kubeconfig -f -
}

gcloud compute ssh controller-0 --command "$(typeset -f create_kubelet_clusterrole kubelet_clusterrolebinding);create_kubelet_clusterrole;kubelet_clusterrolebinding"
