#!/bin/bash -e
echo "##################################################"
echo "Install shipyard if you do not have it installed"
echo "curl https://shipyard.demo.gs/install.sh | bash"
echo "##################################################"

yard up --enable-consul false

echo ""
echo ""

yard push --image docker.pkg.github.com/nicholasjackson/demo-vault/vault-k8s:0.1.0
yard push --image docker.pkg.github.com/nicholasjackson/demo-vault/vault:1.3.1

echo ""
echo ""

export KUBECONFIG="$HOME/.shipyard/yards/shipyard/kubeconfig.yml"
helm install -f ./helm/vault-values.yaml vault ./helm/vault-helm-master

echo ""
echo ""
echo ""
echo "Set the following environment variables:"
echo ""
echo "export KUBECONFIG=\"$$HOME/.shipyard/yards/shipyard/kubeconfig.yml\""
echo "export VAULT_ADDR=\"http://localhost:8200\""
echo "export VAULT_TOKEN=\"root\""