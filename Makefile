# ~/techstore/Makefile

# Цвета для вывода
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
RED    := $(shell tput -Txterm setaf 1)
BLUE   := $(shell tput -Txterm setaf 4)
RESET  := $(shell tput -Txterm sgr0)

# Переменные
KIND_CLUSTER_NAME = techstore
NAMESPACE = techstore
INFRA_DIR = techstore-infra

.PHONY: help
help: ## Показать все доступные команды
	@echo "${BLUE}================================================================${RESET}"
	@echo "${YELLOW}   🚀 TechStore Микросервисная Платформа - Команды управления${RESET}"
	@echo "${BLUE}================================================================${RESET}"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  ${GREEN}%-22s${RESET} %s\n", $$1, $$2}'
	@echo "${BLUE}================================================================${RESET}"

## --- ИНФРАСТРУКТУРА ---

.PHONY: infra-up
infra-up: ## Поднять Kind + Postgres (с базами) + Kong
	@echo "${BLUE}=== 1. Создаем Kind кластер ===${RESET}"
	kind create cluster --config $(INFRA_DIR)/kind/cluster.yaml || true

	@echo "${BLUE}=== 2. Добавляем Helm репозитории ===${RESET}"
	helm repo add kong https://charts.konghq.com || true
	helm repo update

	@echo "${BLUE}=== 3. Устанавливаем Postgres ===${RESET}"
	kubectl create namespace $(NAMESPACE) || true
	helm upgrade --install postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
		-f $(INFRA_DIR)/postgres/values.yaml \
		-n $(NAMESPACE)

	@echo "${YELLOW}Ожидаем полной готовности Postgres (это может занять минуту)...${RESET}"
	kubectl rollout status statefulset/postgres-postgresql -n $(NAMESPACE) --timeout=180s
	sleep 3

	@echo "${BLUE}=== 4. Создаем базы данных и права ===${RESET}"
	@export POSTGRES_PASSWORD=$$(kubectl get secret --namespace $(NAMESPACE) postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d); \
	kubectl exec -n $(NAMESPACE) postgres-postgresql-0 -- env PGPASSWORD=$$POSTGRES_PASSWORD psql -U postgres -c 'CREATE DATABASE users;' || true; \
	kubectl exec -n $(NAMESPACE) postgres-postgresql-0 -- env PGPASSWORD=$$POSTGRES_PASSWORD psql -U postgres -c 'CREATE DATABASE catalog;' || true; \
	kubectl exec -n $(NAMESPACE) postgres-postgresql-0 -- env PGPASSWORD=$$POSTGRES_PASSWORD psql -U postgres -d users -c 'GRANT ALL ON SCHEMA public TO techstore;' || true; \
	kubectl exec -n $(NAMESPACE) postgres-postgresql-0 -- env PGPASSWORD=$$POSTGRES_PASSWORD psql -U postgres -d catalog -c 'GRANT ALL ON SCHEMA public TO techstore;' || true

	@echo "${BLUE}=== 5. Устанавливаем Kong ===${RESET}"
	kubectl create configmap kong-declarative-config --from-file=kong.yml=$(INFRA_DIR)/kong/kong.yml -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install kong kong/kong -n $(NAMESPACE) -f $(INFRA_DIR)/kong/kong-values.yaml
	@echo "${GREEN}✅ Инфраструктура готова!${RESET}"

.PHONY: infra-down
infra-down: ## Удалить Kind кластер (ОСТОРОЖНО: удалит все данные)
	@echo "${RED}⚠️  ВНИМАНИЕ: Удаление кластера уничтожит все данные!${RESET}"
	kind delete cluster --name $(KIND_CLUSTER_NAME)

## --- СЕРВИСЫ (СБОРКА И ДЕПЛОЙ) ---

.PHONY: user-build
user-build: ## Собрать Docker-образ user-service (Go)
	@echo "${BLUE}=== Сборка user-service (Go) ===${RESET}"
	cd techstore-user-service && docker build -t user-service:0.1.0 .

.PHONY: user-deploy
user-deploy: user-build ## Задеплоить user-service (с авто-миграциями)
	@echo "${BLUE}=== Деплой user-service ===${RESET}"
	@echo "${YELLOW}Загружаем образ в Kind...${RESET}"
	kind load docker-image user-service:0.1.0 --name $(KIND_CLUSTER_NAME)
	@echo "${YELLOW}Запускаем Helm (с миграциями БД)...${RESET}"
	helm upgrade --install user-service $(INFRA_DIR)/helm/service-template -f techstore-user-service/deploy/values.yaml -n $(NAMESPACE)
	@echo "${GREEN}✅ user-service задеплоен!${RESET}"

.PHONY: catalog-build
catalog-build: ## Собрать Docker-образ catalog-service (Java)
	@echo "${BLUE}=== Сборка catalog-service (Java) ===${RESET}"
	cd techstore-catalog-service && docker build -t catalog-service:0.1.0 .

.PHONY: catalog-deploy
catalog-deploy: catalog-build ## Задеплоить catalog-service (с авто-миграциями)
	@echo "${BLUE}=== Деплой catalog-service ===${RESET}"
	@echo "${YELLOW}Загружаем образ в Kind...${RESET}"
	kind load docker-image catalog-service:0.1.0 --name $(KIND_CLUSTER_NAME)
	@echo "${YELLOW}Запускаем Helm (с миграциями БД)...${RESET}"
	helm upgrade --install catalog-service $(INFRA_DIR)/helm/service-template -f techstore-catalog-service/deploy/values.yaml -n $(NAMESPACE)
	@echo "${GREEN}✅ catalog-service задеплоен!${RESET}"

.PHONY: deploy-all
deploy-all: user-deploy catalog-deploy ## Задеплоить все сервисы разом
	@echo "${GREEN}✅ Все сервисы успешно задеплоены!${RESET}"

## --- ЛОГИ И ОТЛАДКА ---

.PHONY: logs-user
logs-user: ## Смотреть логи user-service в реальном времени
	kubectl logs -n $(NAMESPACE) -l app=user-service -f --tail=50

.PHONY: logs-catalog
logs-catalog: ## Смотреть логи catalog-service в реальном времени
	kubectl logs -n $(NAMESPACE) -l app=catalog-service -f --tail=50

.PHONY: logs-kong
logs-kong: ## Смотреть логи Kong Gateway
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=kong -c proxy -f --tail=50

.PHONY: logs-migrate
logs-migrate: ## Смотреть логи последнего Job'а миграций
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l job-name --sort-by=.metadata.creationTimestamp -o jsonpath="{.items[-1:].metadata.name}"); \
	if [ -z "$$POD" ]; then echo "${YELLOW}Job'ы миграций не найдены.${RESET}"; else kubectl logs -n $(NAMESPACE) $$POD; fi

.PHONY: describe-user
describe-user: ## Показать детали (Events) для пода user-service
	kubectl describe pod -n $(NAMESPACE) -l app=user-service

.PHONY: describe-catalog
describe-catalog: ## Показать детали (Events) для пода catalog-service
	kubectl describe pod -n $(NAMESPACE) -l app=catalog-service

## --- МОНИТОРИНГ И ДОСТУП ---

.PHONY: monitoring-up
monitoring-up: ## Установить Prometheus + Grafana
	@echo "${BLUE}=== Устанавливаем мониторинг ===${RESET}"
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
	helm repo update
	kubectl create namespace monitoring || true
	helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring -f monitoring-values.yaml
	@echo "${GREEN}✅ Мониторинг установлен!${RESET}"

.PHONY: monitoring-port-forward
monitoring-port-forward: ## Открыть Grafana на localhost:3000
	@echo "${YELLOW}Открываем Grafana: http://localhost:3000${RESET}"
	kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring

.PHONY: api-port-forward
api-port-forward: ## Открыть Kong API на localhost:8080
	@echo "${YELLOW}Открываем API Gateway: http://localhost:8080${RESET}"
	kubectl port-forward -n $(NAMESPACE) svc/kong-kong-proxy 8080:80

.PHONY: status
status: ## Показать статус всех подов (красиво)
	@echo "${BLUE}=== Статус сервисов TechStore ===${RESET}"
	@kubectl get pods -n $(NAMESPACE)
	@echo ""
	@echo "${BLUE}=== Статус мониторинга ===${RESET}"
	@kubectl get pods -n monitoring 2>/dev/null || echo "${YELLOW}Мониторинг не установлен.${RESET}"