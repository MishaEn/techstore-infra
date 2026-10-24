# ~/techstore/techstore-infra/Makefile

# ==============================================================================
#  🎨 ЦВЕТА И СТИЛИ
# ==============================================================================
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
RED    := $(shell tput -Txterm setaf 1)
BLUE   := $(shell tput -Txterm setaf 4)
CYAN   := $(shell tput -Txterm setaf 6)
WHITE  := $(shell tput -Txterm setaf 7)
BOLD   := $(shell tput -Txterm bold)
RESET  := $(shell tput -Txterm sgr0)

# ==============================================================================
#  ⚙️ ПЕРЕМЕННЫЕ
# ==============================================================================
KIND_CLUSTER_NAME ?= techstore
NAMESPACE         ?= techstore
DOCKER_TAG        ?= 0.1.0

# Пути к сервисам (они лежат на уровень выше)
USER_DIR    ?= ../techstore-user-service
CATALOG_DIR ?= ../techstore-catalog-service
ORDER_DIR   ?= ../techstore-order-service

# ==============================================================================
#  📋 ОСНОВНЫЕ ЦЕЛИ
# ==============================================================================
.PHONY: help
help: ## 📖 Показать все доступные команды
	@echo ""
	@echo "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
	@echo "${BLUE}║${RESET}  ${BOLD}${WHITE}🚀 TechStore Микросервисная Платформа - Панель управления${RESET}            ${BLUE}║${RESET}"
	@echo "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  ${GREEN}%-24s${RESET} %s\n", $$1, $$2}'
	@echo ""
	@echo "${BLUE}──────────────────────────────────────────────────────────────────────${RESET}"
	@echo "  ${YELLOW}💡 Подсказка:${RESET} используйте ${GREEN}make <команда>${RESET} для запуска."
	@echo ""

# ==============================================================================
#  🏗️  ИНФРАСТРУКТУРА
# ==============================================================================
.PHONY: infra-up
infra-up: ## 🏗️  Поднять Kind + Postgres (с базами) + Kong
	@echo ""
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  🏗️  РАЗВЕРТЫВАНИЕ ИНФРАСТРУКТУРЫ${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"

	@echo "${YELLOW}▶ 1/5 Создаем Kind кластер...${RESET}"
	@kind create cluster --config kind/cluster.yaml || true

	@echo "${YELLOW}▶ 2/5 Добавляем Helm репозитории...${RESET}"
	@helm repo add kong https://charts.konghq.com || true
	@helm repo update > /dev/null 2>&1

	@echo "${YELLOW}▶ 3/5 Устанавливаем Postgres...${RESET}"
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f - > /dev/null
	@helm upgrade --install postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
		-f postgres/values.yaml \
		-n $(NAMESPACE) > /dev/null

	@echo "${YELLOW}   Ожидаем готовности Postgres (это может занять минуту)...${RESET}"
	@kubectl rollout status statefulset/postgres-postgresql -n $(NAMESPACE) --timeout=180s
	@sleep 3

	@echo "${YELLOW}▶ 4/5 Создаем базы данных и права...${RESET}"
	@export POSTGRES_PASSWORD=$$(kubectl get secret --namespace $(NAMESPACE) postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d); \
	for db in users catalog orders; do \
		kubectl exec -n $(NAMESPACE) postgres-postgresql-0 -- env PGPASSWORD=$$POSTGRES_PASSWORD psql -U postgres -c "CREATE DATABASE $$db OWNER techstore;" 2>/dev/null || true; \
		kubectl exec -n $(NAMESPACE) postgres-postgresql-0 -- env PGPASSWORD=$$POSTGRES_PASSWORD psql -U postgres -d $$db -c "GRANT ALL ON SCHEMA public TO techstore;" 2>/dev/null || true; \
		echo "   ✅ База $$db готова (владелец: techstore)"; \
	done

	@echo "${YELLOW}▶ 5/5 Устанавливаем Kong Gateway...${RESET}"
	@kubectl create configmap kong-declarative-config --from-file=kong.yml=kong/kong.yml -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f - > /dev/null
	@helm upgrade --install kong kong/kong -n $(NAMESPACE) -f kong/kong-values.yaml > /dev/null

	@echo ""
	@echo "${GREEN}✅ Инфраструктура успешно развернута!${RESET}"
	@echo ""

.PHONY: infra-down
infra-down: ## 🗑️  Удалить Kind кластер (ОСТОРОЖНО: удалит все данные)
	@echo ""
	@echo "${RED}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
	@echo "${RED}║  ⚠️  ВНИМАНИЕ: Удаление кластера уничтожит ВСЕ данные!               ║${RESET}"
	@echo "${RED}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
	@read -p "  Вы уверены? Введите ${YELLOW}yes${RESET} для подтверждения: " confirm; \
	if [ "$$confirm" != "yes" ]; then echo "  ${YELLOW}Отменено.${RESET}"; exit 1; fi
	@echo "${YELLOW}▶ Удаляем кластер...${RESET}"
	@kind delete cluster --name $(KIND_CLUSTER_NAME)
	@echo "${GREEN}✅ Кластер удален.${RESET}"

# ==============================================================================
#  📦 СЕРВИСЫ (СБОРКА И ДЕПЛОЙ)
# ==============================================================================
.PHONY: user-build
user-build: ## 📦 Собрать Docker-образ user-service (Go)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  🐹 СБОРКА USER-SERVICE (Go)${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@cd $(USER_DIR) && docker build -t user-service:$(DOCKER_TAG) .
	@echo "${GREEN}✅ Образ user-service:$(DOCKER_TAG) собран.${RESET}"

.PHONY: user-build-nc
user-build-nc: ## 🧹 Собрать Docker-образ user-service (БЕЗ КЕША)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${RED}  🐹 СБОРКА USER-SERVICE БЕЗ КЕША${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@cd $(USER_DIR) && docker build --no-cache -t user-service:$(DOCKER_TAG) .
	@echo "${GREEN}✅ Образ user-service:$(DOCKER_TAG) собран.${RESET}"

.PHONY: user-deploy
user-deploy: user-build ## 🚀 Задеплоить user-service (с авто-миграциями)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  🚀 ДЕПЛОЙ USER-SERVICE${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${YELLOW}▶ Загружаем образ в Kind...${RESET}"
	@kind load docker-image user-service:$(DOCKER_TAG) --name $(KIND_CLUSTER_NAME)
	@echo "${YELLOW}▶ Запускаем Helm (с миграциями БД)...${RESET}"
	@helm upgrade --install user-service helm/service-template \
		-f $(USER_DIR)/deploy/values.yaml \
		-n $(NAMESPACE)
	@kubectl rollout restart deployment user-service -n $(NAMESPACE)
	@echo "${GREEN}✅ user-service успешно задеплоен!${RESET}"

.PHONY: user-deploy-nc
user-deploy-nc: user-build-nc ## 🚀 Задеплоить user-service (БЕЗ КЕША)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${RED}  🚀 ДЕПЛОЙ USER-SERVICE БЕЗ КЕША${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${YELLOW}▶ Загружаем образ в Kind...${RESET}"
	@kind load docker-image user-service:$(DOCKER_TAG) --name $(KIND_CLUSTER_NAME)
	@echo "${YELLOW}▶ Запускаем Helm (с миграциями БД)...${RESET}"
	@helm upgrade --install user-service helm/service-template \
		-f $(USER_DIR)/deploy/values.yaml \
		-n $(NAMESPACE)
	@kubectl rollout restart deployment user-service -n $(NAMESPACE)
	@echo "${GREEN}✅ user-service успешно задеплоен!${RESET}"

.PHONY: catalog-build
catalog-build: ## ☕ Собрать Docker-образ catalog-service (Java)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  ☕ СБОРКА CATALOG-SERVICE (Java)${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@cd $(CATALOG_DIR) && docker build -t catalog-service:$(DOCKER_TAG) .
	@echo "${GREEN}✅ Образ catalog-service:$(DOCKER_TAG) собран.${RESET}"

.PHONY: catalog-build-nc
catalog-build-nc: ## 🧹 Собрать Docker-образ catalog-service (БЕЗ КЕША)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${RED}  ☕ СБОРКА CATALOG-SERVICE БЕЗ КЕША${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@cd $(CATALOG_DIR) && docker build --no-cache -t catalog-service:$(DOCKER_TAG) .
	@echo "${GREEN}✅ Образ catalog-service:$(DOCKER_TAG) собран.${RESET}"

.PHONY: catalog-deploy
catalog-deploy: catalog-build ## 🚀 Задеплоить catalog-service (с авто-миграциями)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  🚀 ДЕПЛОЙ CATALOG-SERVICE${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${YELLOW}▶ Загружаем образ в Kind...${RESET}"
	@kind load docker-image catalog-service:$(DOCKER_TAG) --name $(KIND_CLUSTER_NAME)
	@echo "${YELLOW}▶ Запускаем Helm (с миграциями БД)...${RESET}"
	@helm upgrade --install catalog-service helm/service-template \
		-f $(CATALOG_DIR)/deploy/values.yaml \
		-n $(NAMESPACE)
	@kubectl rollout restart deployment catalog-service -n $(NAMESPACE)
	@echo "${GREEN}✅ catalog-service успешно задеплоен!${RESET}"

.PHONY: catalog-deploy-nc
catalog-deploy-nc: catalog-build-nc ## 🚀 Задеплоить catalog-service (БЕЗ КЕША)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${RED}  🚀 ДЕПЛОЙ CATALOG-SERVICE БЕЗ КЕША${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${YELLOW}▶ Загружаем образ в Kind...${RESET}"
	@kind load docker-image catalog-service:$(DOCKER_TAG) --name $(KIND_CLUSTER_NAME)
	@echo "${YELLOW}▶ Запускаем Helm (с миграциями БД)...${RESET}"
	@helm upgrade --install catalog-service helm/service-template \
		-f $(CATALOG_DIR)/deploy/values.yaml \
		-n $(NAMESPACE)
	@kubectl rollout restart deployment catalog-service -n $(NAMESPACE)
	@echo "${GREEN}✅ catalog-service успешно задеплоен!${RESET}"

.PHONY: order-build
order-build: ## 🛒 Собрать Docker-образ order-service (Go)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  🛒 СБОРКА ORDER-SERVICE (Go)${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@cd $(ORDER_DIR) && docker build -t order-service:$(DOCKER_TAG) .
	@echo "${GREEN}✅ Образ order-service:$(DOCKER_TAG) собран.${RESET}"

.PHONY: order-build-nc
order-build-nc: ## 🧹 Собрать Docker-образ order-service (БЕЗ КЕША)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${RED}  🛒 СБОРКА ORDER-SERVICE БЕЗ КЕША${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@cd $(ORDER_DIR) && docker build --no-cache -t order-service:$(DOCKER_TAG) .
	@echo "${GREEN}✅ Образ order-service:$(DOCKER_TAG) собран.${RESET}"

.PHONY: order-deploy
order-deploy: order-build ## 🚀 Задеплоить order-service (с авто-миграциями)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  🚀 ДЕПЛОЙ ORDER-SERVICE${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${YELLOW}▶ Загружаем образ в Kind...${RESET}"
	@kind load docker-image order-service:$(DOCKER_TAG) --name $(KIND_CLUSTER_NAME)
	@echo "${YELLOW}▶ Запускаем Helm (с миграциями БД)...${RESET}"
	@helm upgrade --install order-service helm/service-template \
		-f $(ORDER_DIR)/deploy/values.yaml \
		-n $(NAMESPACE)
	@kubectl rollout restart deployment order-service -n $(NAMESPACE)
	@echo "${GREEN}✅ order-service успешно задеплоен!${RESET}"

.PHONY: order-deploy-nc
order-deploy-nc: order-build-nc ## 🚀 Задеплоить order-service (БЕЗ КЕША)
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${RED}  🚀 ДЕПЛОЙ ORDER-SERVICE БЕЗ КЕША${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${YELLOW}▶ Загружаем образ в Kind...${RESET}"
	@kind load docker-image order-service:$(DOCKER_TAG) --name $(KIND_CLUSTER_NAME)
	@echo "${YELLOW}▶ Запускаем Helm (с миграциями БД)...${RESET}"
	@helm upgrade --install order-service helm/service-template \
		-f $(ORDER_DIR)/deploy/values.yaml \
		-n $(NAMESPACE)
	@kubectl rollout restart deployment order-service -n $(NAMESPACE)
	@echo "${GREEN}✅ order-service успешно задеплоен!${RESET}"

.PHONY: deploy-all
deploy-all: user-deploy catalog-deploy order-deploy ## 🚀 Задеплоить все сервисы разом
	@echo ""
	@echo "${GREEN}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${GREEN}  🎉 ВСЕ СЕРВИСЫ УСПЕШНО ЗАДЕПЛОЕНЫ!${RESET}"
	@echo "${GREEN}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo ""

.PHONY: deploy-all-nc
deploy-all-nc: user-deploy-nc catalog-deploy-nc order-deploy-nc ## 🚀 Задеплоить все сервисы разом (БЕЗ КЕША)
	@echo ""
	@echo "${GREEN}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${GREEN}  🎉 ВСЕ СЕРВИСЫ УСПЕШНО ЗАДЕПЛОЕНЫ! (БЕЗ КЕША)${RESET}"
	@echo "${GREEN}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo ""

# ==============================================================================
#  🔄 ПЕРЕЗАПУСК И ОЧИСТКА
# ==============================================================================
.PHONY: restart-user
restart-user: ## 🔄 Перезапустить под user-service
	@echo "${YELLOW}▶ Перезапускаем user-service...${RESET}"
	@kubectl rollout restart deployment user-service -n $(NAMESPACE)

.PHONY: restart-catalog
restart-catalog: ## 🔄 Перезапустить под catalog-service
	@echo "${YELLOW}▶ Перезапускаем catalog-service...${RESET}"
	@kubectl rollout restart deployment catalog-service -n $(NAMESPACE)

.PHONY: restart-order
restart-order: ## 🔄 Перезапустить под order-service
	@echo "${YELLOW}▶ Перезапускаем order-service...${RESET}"
	@kubectl rollout restart deployment order-service -n $(NAMESPACE)

.PHONY: restart-all
restart-all: ## 🔄 Перезапустить ВСЕ сервисы разом
	@echo "${YELLOW}▶ Перезапускаем все сервисы...${RESET}"
	@kubectl rollout restart deployment user-service -n $(NAMESPACE)
	@kubectl rollout restart deployment catalog-service -n $(NAMESPACE)
	@kubectl rollout restart deployment order-service -n $(NAMESPACE)
	@echo "${GREEN}✅ Все поды перезапущены.${RESET}"

.PHONY: clean-jobs
clean-jobs: ## 🧹 Удалить все Job'ы миграций (если зависли)
	@echo "${YELLOW}▶ Удаляем все Job'ы в namespace $(NAMESPACE)...${RESET}"
	@kubectl delete job -n $(NAMESPACE) --all
	@echo "${GREEN}✅ Job'ы удалены.${RESET}"

# ==============================================================================
#  📜 ЛОГИ И ОТЛАДКА
# ==============================================================================
.PHONY: logs-user
logs-user: ## 📜 Логи user-service (реальное время)
	@echo "${YELLOW}▶ Поток логов user-service (Ctrl+C для выхода)...${RESET}"
	@kubectl logs -n $(NAMESPACE) -l app=user-service -f --tail=50

.PHONY: logs-catalog
logs-catalog: ## 📜 Логи catalog-service (реальное время)
	@echo "${YELLOW}▶ Поток логов catalog-service (Ctrl+C для выхода)...${RESET}"
	@kubectl logs -n $(NAMESPACE) -l app=catalog-service -f --tail=50

.PHONY: logs-order
logs-order: ## 📜 Логи order-service (реальное время)
	@echo "${YELLOW}▶ Поток логов order-service (Ctrl+C для выхода)...${RESET}"
	@kubectl logs -n $(NAMESPACE) -l app=order-service -f --tail=50

.PHONY: logs-kong
logs-kong: ## 📜 Логи Kong Gateway
	@echo "${YELLOW}▶ Поток логов Kong (Ctrl+C для выхода)...${RESET}"
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=kong -c proxy -f --tail=50

.PHONY: logs-migrate
logs-migrate: ## 📜 Логи последнего Job'а миграций
	@echo "${YELLOW}▶ Ищем последний Job миграций...${RESET}"
	@POD=$$(kubectl get pods -n $(NAMESPACE) -l job-name --sort-by=.metadata.creationTimestamp -o jsonpath="{.items[-1:].metadata.name}"); \
	if [ -z "$$POD" ]; then \
		echo "${YELLOW}Job'ы миграций не найдены.${RESET}"; \
	else \
		echo "${GREEN}Найден под: $$POD${RESET}"; \
		kubectl logs -n $(NAMESPACE) $$POD; \
	fi

# ==============================================================================
#  🗄️  РАБОТА С БАЗОЙ ДАННЫХ
# ==============================================================================
.PHONY: db-users
db-users: ## 🗄️  Зайти в базу данных users (psql)
	@echo "${YELLOW}▶ Подключение к БД users...${RESET}"
	@kubectl exec -it -n $(NAMESPACE) postgres-postgresql-0 -- env PGPASSWORD=dev-techstore-pass psql -U techstore -d users

.PHONY: db-catalog
db-catalog: ## 🗄️  Зайти в базу данных catalog (psql)
	@echo "${YELLOW}▶ Подключение к БД catalog...${RESET}"
	@kubectl exec -it -n $(NAMESPACE) postgres-postgresql-0 -- env PGPASSWORD=dev-techstore-pass psql -U techstore -d catalog

.PHONY: db-orders
db-orders: ## 🗄️  Зайти в базу данных orders (psql)
	@echo "${YELLOW}▶ Подключение к БД orders...${RESET}"
	@kubectl exec -it -n $(NAMESPACE) postgres-postgresql-0 -- env PGPASSWORD=dev-techstore-pass psql -U techstore -d orders

# ==============================================================================
#  📊 МОНИТОРИНГ И ДОСТУП
# ==============================================================================
.PHONY: monitoring-up
monitoring-up: ## 📊 Установить Prometheus + Grafana
	@echo ""
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  📊 УСТАНОВКА МОНИТОРИНГА${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${YELLOW}▶ Добавляем репозиторий Prometheus...${RESET}"
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
	@helm repo update > /dev/null 2>&1
	@echo "${YELLOW}▶ Создаем namespace monitoring...${RESET}"
	@kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - > /dev/null
	@echo "${YELLOW}▶ Устанавливаем kube-prometheus-stack...${RESET}"
	@helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring -f monitoring-values.yaml
	@echo "${GREEN}✅ Мониторинг установлен!${RESET}"

.PHONY: monitoring-port-forward
monitoring-port-forward: ## 🌐 Открыть Grafana на localhost:3000
	@echo ""
	@echo "${GREEN}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${GREEN}  📊 Grafana доступна по адресу: ${BOLD}http://localhost:3000${RESET}"
	@echo "${GREEN}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo ""
	@kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring

.PHONY: api-port-forward
api-port-forward: ## 🌐 Открыть Kong API на localhost:8080
	@echo ""
	@echo "${GREEN}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${GREEN}  🌐 API Gateway доступен по адресу: ${BOLD}http://localhost:8080${RESET}"
	@echo "${GREEN}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo ""
	@kubectl port-forward -n $(NAMESPACE) svc/kong-kong-proxy 8080:80

.PHONY: status
status: ## 📈 Показать статус всех подов (красиво)
	@echo ""
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  📈 СТАТУС СЕРВИСОВ TECHSTORE${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@kubectl get pods -n $(NAMESPACE)
	@echo ""
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@echo "${BOLD}${CYAN}  📈 СТАТУС МОНИТОРИНГА${RESET}"
	@echo "${BLUE}═══════════════════════════════════════════════════════════════════════${RESET}"
	@kubectl get pods -n monitoring 2>/dev/null || echo "  ${YELLOW}Мониторинг не установлен.${RESET}"
	@echo ""