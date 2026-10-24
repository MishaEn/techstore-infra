# TechStore: Полиглотная Микросервисная Платформа

Добро пожаловать в TechStore. Это учебный, но полностью рабочий проект микросервисной архитектуры для интернет-магазина электроники. Проект демонстрирует, как разные языки программирования (Go и Java) могут работать вместе в едином кластере Kubernetes, общаясь через API Gateway.

## Архитектура

Платформа состоит из следующих компонентов:

*   **API Gateway (Kong):** Единая точка входа. Маршрутизирует запросы и проверяет JWT-токены.
*   **User Service (Go):** Отвечает за регистрацию, аутентификацию и профили пользователей.
*   **Catalog Service (Java / Spring Boot):** Отвечает за каталог товаров.
*   **Order Service (Go):** Отвечает за создание заказов и взаимодействует с Catalog Service для проверки цен.
*   **PostgreSQL:** Единый инстанс базы данных, но с изолированными базами (`users`, `catalog`, `orders`) для каждого сервиса (паттерн Database-per-Service).
*   **Мониторинг (Prometheus + Grafana):** Сбор метрик и визуализация состояния системы.
*   **Headlamp:** Веб-интерфейс для управления Kubernetes-кластером.

### Стек технологий

*   **Языки:** Go 1.26, Java 21 (Spring Boot 4.0)
*   **Инфраструктура:** Docker, Kubernetes (Kind), Helm
*   **Базы данных:** PostgreSQL 18
*   **API Gateway:** Kong (DB-less режим)
*   **Миграции:** Goose (для Go-сервисов), Flyway (для Java-сервиса)

---

## Структура репозиториев

Проект разделен на независимые репозитории, которые для удобства управления клонируются в одну корневую папку `techstore`:

1.  [techstore-infra](https://github.com/MishaEn/techstore-infra) — Инфраструктура (Kind, Postgres, Kong, Helm-шаблоны, Makefile, CI/CD).
2.  [techstore-user-service](https://github.com/MishaEn/techstore-user-service) — Исходный код сервиса пользователей на Go.
3.  [techstore-catalog-service](https://github.com/MishaEn/techstore-catalog-service) — Исходный код сервиса каталога на Java.
4.  [techstore-order-service](https://github.com/MishaEn/techstore-order-service) — Исходный код сервиса заказов на Go.

---

## Быстрый старт (Локальная разработка)

### Требования
На вашем компьютере (в WSL2/Ubuntu) должны быть установлены:
*   Docker (с поддержкой WSL2)
*   `kubectl`
*   `kind`
*   `helm` (версия 3.12+)
*   `make`
*   `git`

### Установка

1.  Клонируйте все четыре репозитория в одну папку:
    ```bash
    mkdir -p ~/techstore && cd ~/techstore
    git clone https://github.com/MishaEn/techstore-infra.git
    git clone https://github.com/MishaEn/techstore-user-service.git
    git clone https://github.com/MishaEn/techstore-catalog-service.git
    git clone https://github.com/MishaEn/techstore-order-service.git
    ```

2.  Перейдите в папку инфраструктуры и поднимите кластер:
    ```bash
    cd techstore-infra
    make infra-up
    ```
    *Скрипт создаст кластер Kind, поднимет Postgres, создаст базы данных (`users`, `catalog`, `orders`) и настроит Kong.*

3.  Соберите и разверните все микросервисы:
    ```bash
    make deploy-all-nc
    ```
    *(Флаг `-nc` означает сборку Docker-образов без кэша, чтобы гарантировать применение последних изменений. Helm автоматически применит миграции баз данных перед запуском сервисов).*

4.  Проверьте статус (все поды должны быть `1/1 Running`):
    ```bash
    make status
    ```

5.  Откройте API Gateway для доступа извне:
    ```bash
    make api-port-forward
    ```
    *(Оставьте этот терминал открытым).*

---

## Примеры API-запросов

**1. Регистрация пользователя (User Service)**
```bash
curl -X POST http://localhost:8080/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password","full_name":"Test User"}'
```

**2. Логин (получение JWT-токена)**
```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password"}'
```
*(Скопируйте `access_token` из ответа).*

**3. Получение списка товаров (Catalog Service, публичный маршрут)**
```bash
curl http://localhost:8080/api/v1/products
```

**4. Создание заказа (Order Service вызывает Catalog Service)**
```bash
curl -X POST http://localhost:8080/api/v1/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ВАШ_ТОКЕН>" \
  -d '{"items":[{"product_id":"<ID_ТОВАРА>","quantity":2}]}'
```

---

## Полезные команды (Makefile)

Вся рутина автоматизирована. Выполните `make help`, чтобы увидеть полный список. Основные команды:

*   `make status` — Показать статус всех подов.
*   `make logs-user` — Смотреть логи Go-сервиса пользователей.
*   `make logs-catalog` — Смотреть логи Java-сервиса каталога.
*   `make logs-order` — Смотреть логи Go-сервиса заказов.
*   `make logs-kong` — Смотреть логи API Gateway.
*   `make restart-all` — Перезапустить все поды.
*   `make monitoring-up` — Установить Prometheus и Grafana.
*   `make monitoring-port-forward` — Открыть Grafana (localhost:3000).
*   `make infra-down` — **ВНИМАНИЕ:** Полностью удалить кластер и все данные.

---

## Подключение к базе данных

Каждый сервис имеет свою изолированную базу данных, но в локальной среде они живут в одном инстансе PostgreSQL. Для быстрого подключения используйте команды из Makefile:

*   `make db-users` — подключение к базе пользователей.
*   `make db-catalog` — подключение к базе каталога.
*   `make db-orders` — подключение к базе заказов.

**Параметры подключения (вручную):**
*   Host: `localhost` (при использовании `kubectl port-forward`)
*   Port: `5432`
*   Пользователь: `techstore`
*   Пароль: `dev-techstore-pass`

---

## Безопасность

*   **JWT-токены:** Подписываются алгоритмом RS256. Приватный и публичный ключи хранятся в Kubernetes Secret и передаются сервисам через переменные окружения.
*   **API Gateway:** Kong проверяет подпись токена для всех защищенных маршрутов (например, `/api/v1/users/me`, `/api/v1/orders`), прежде чем пропустить запрос в сервис. Сами сервисы доверяют заголовкам, пришедшим от Gateway.