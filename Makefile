SHELL := /bin/bash
ACCOUNT_NAME = terraform
ACCOUNT_DISPLAY_NAME = Terraform SA for cluster
ACCOUNT_DESCRIPTION = Terraform service account for Cluster
PROJECT_NAME := dinsurance
SA_EMAIL = $(ACCOUNT_NAME)@$(PROJECT_NAME).iam.gserviceaccount.com
KEY_FILE = key.json
MAIN_REGION = us-central1
CLUSTER_NAME = dinsurance


export GOOGLE_CLOUD_KEYFILE_JSON =$(KEY_FILE)

.PHONY : ready

ready :
	@gcloud config set project $(PROJECT_NAME)
	@gcloud services enable compute.googleapis.com
	@gcloud services enable cloudresourcemanager.googleapis.com
	@gcloud services enable container.googleapis.com

.PHONY : sa-create sa-delete

sa-create :
ifeq ($(shell gcloud iam service-accounts list --filter=name:$(ACCOUNT_NAME) --format="value(name)"), projects/$(PROJECT_NAME)/serviceAccounts/$(ACCOUNT_NAME)@$(PROJECT_NAME).iam.gserviceaccount.com)
	@echo Account exists
else
	@gcloud iam service-accounts create $(ACCOUNT_NAME)
endif

sa-display-name : sa-create
	@gcloud iam service-accounts update --display-name "$(ACCOUNT_DISPLAY_NAME)" $(SA_EMAIL)

sa-description : sa-display-name
	@gcloud iam service-accounts update --description "$(ACCOUNT_DESCRIPTION)" $(SA_EMAIL)

sa-access-key : sa-create
	@gcloud iam service-accounts keys create $(KEY_FILE) --iam-account $(SA_EMAIL)

sa-roles : sa-create
	declare -a roles=("roles/editor" "roles/container.admin" "roles/iam.serviceAccountAdmin" "roles/resourcemanager.projectIamAdmin"); \
	for role in "$${roles[@]}"; do gcloud projects add-iam-policy-binding $(PROJECT_NAME) --member serviceAccount:$(SA_EMAIL) --role $$role > /dev/null; done

sa-delete :
	@gcloud iam service-accounts delete --quiet $(SA_EMAIL)


.PHONY : create-cluster

create-cluster :
	@terraform init
	@terraform plan -out plan
	@terraform apply plan

get-credentials :
	gcloud container clusters get-credentials --region=$(MAIN_REGION) $(CLUSTER_NAME)

helm-repo :
	helm repo add stable https://kubernetes-charts.storage.googleapis.com/
	helm repo add bitnami https://charts.bitnami.com/bitnami

destroy-cluster :
	@terraform destroy -auto-approve

ingress-deploy :
	helm install external stable/nginx-ingress --values=./helm/ingress/values.yaml

ingress-upgrade :
	helm upgrade --install external stable/nginx-ingress --values=./helm/ingress/values.yaml

ingress-destroy :
	helm uninstall external

prom-deploy :
	helm install prometheus stable/prometheus-operator --values=./helm/prometheus-operator/values.yaml --version=8.12.3

prom-upgrade :
	helm upgrade --install prometheus stable/prometheus-operator --values=./helm/prometheus-operator/values.yaml --version=8.12.3

prom-destroy :
	helm uninstall prometheus
	kubectl delete crd prometheusrules.monitoring.coreos.com
	kubectl delete crd servicemonitors.monitoring.coreos.com
	kubectl delete crd alertmanagers.monitoring.coreos.com
	kubectl delete crd prometheuses.monitoring.coreos.com
	kubectl delete crd podmonitors.monitoring.coreos.com

