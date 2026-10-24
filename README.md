# 🛍️ TechStore — Полиглотная Микросервисная Платформа

Добро пожаловать в TechStore! Это учебный, но полностью рабочий проект микросервисной архитектуры для интернет-магазина электроники. Проект демонстрирует, как разные языки программирования (Go и Java) могут работать вместе в едином кластере Kubernetes, общаясь через API Gateway.

## 🏗️ Архитектура

Платформа состоит из следующих компонентов:

*   **API Gateway (Kong):** Единая точка входа. Маршрутизирует запросы и проверяет JWT-токены.
*   **User Service (Go):** Отвечает за регистрацию, аутентификацию и профили пользователей.
*   **Catalog Service (Java / Spring Boot):** Отвечает за каталог товаров.
*   **PostgreSQL:** Единый инстанс базы данных, но с изолированными базами (`users` и `catalog`) для каждого сервиса (паттерн Database-per-Service).
*   **Мониторинг (Prometheus + Grafana):** Сбор метрик и визуализация состояния системы (опционально).
*   **Headlamp:** Веб-интерфейс для управления Kubernetes-кластером.

### Стек технологий:
*   **Языки:** Go 1.26, Java 21 (Spring Boot 4.0)
*   **Инфраструктура:** Docker, Kubernetes (Kind), Helm
*   **Базы данных:** PostgreSQL 18
*   **API Gateway:** Kong (DB-less режим)
*   **Миграции:** Goose (для Go), Flyway (для Java)

---

## 📂 Структура репозиториев

Проект разделен на три независимых репозитория:

1.  `techstore-infra` — Инфраструктура (Kind, Postgres, Kong, Helm-шаблоны, CI/CD).
2.  `techstore-user-service` — Исходный код сервиса на Go.
3.  `techstore-catalog-service` — Исходный код сервиса на Java.

Для удобства управления они клонируются в одну корневую папку `techstore`.

---

## 🚀 Быстрый старт (Локальная разработка)

### Требования
На вашем компьютере (в WSL2/Ubuntu) должны быть установлены:
*   Docker (с поддержкой WSL2)
*   `kubectl`
*   `kind`
*   `helm` (версия 3.12+)
*   `make`
*   `git`

### Установка

1.  Клонируйте все три репозитория в одну папку:
    ```bash
    mkdir -p ~/techstore && cd ~/techstore
    git clone <URL_ИНФРАСТРУКТУРЫ> techstore-infra
    git clone <URL_USER_SERVICE> techstore-user-service
    git clone <URL_CATALOG_SERVICE> techstore-catalog-service