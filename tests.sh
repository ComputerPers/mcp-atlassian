#!/bin/bash

# Скрипт для запуска тестов проекта mcp-atlassian локально или в Docker

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Имя файла docker-compose для тестов
TEST_COMPOSE_FILE="docker-compose.test.yml"
# Имя docker сети
DOCKER_NETWORK_NAME="rnd-network"
# Имя сервиса Jira в compose файле
JIRA_SERVICE_NAME="jira-test"
# Имя контейнера Jira (для проверки статуса)
JIRA_CONTAINER_NAME="jira-test-atlassian"

# Печать сообщения с датой и временем
log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- Проверки наличия инструментов --- START
check_command() {
  if ! command -v $1 &> /dev/null; then
    log_message "${RED}Команда '$1' не найдена. Пожалуйста, установите её.${NC}"
    exit 1
  fi
}

check_command docker
check_command docker-compose
# --- Проверки наличия инструментов --- END

# --- Управление тестовым окружением Docker --- START

# Функция для проверки и создания Docker сети
ensure_docker_network() {
  if ! docker network inspect $DOCKER_NETWORK_NAME > /dev/null 2>&1; then
    log_message "${YELLOW}Сеть Docker '$DOCKER_NETWORK_NAME' не найдена. Создание...${NC}"
    docker network create $DOCKER_NETWORK_NAME
    if [ $? -ne 0 ]; then
      log_message "${RED}Не удалось создать сеть Docker '$DOCKER_NETWORK_NAME'.${NC}"
      exit 1
    fi
    log_message "${GREEN}Сеть Docker '$DOCKER_NETWORK_NAME' успешно создана.${NC}"
  else
    log_message "${GREEN}Сеть Docker '$DOCKER_NETWORK_NAME' уже существует.${NC}"
  fi
}

# Функция для запуска тестового окружения Jira
start_test_jira() {
  log_message "${YELLOW}Запуск тестового окружения Jira с помощью $TEST_COMPOSE_FILE...${NC}"
  # Удаляем старые контейнеры, если они остались
  docker-compose -f "$TEST_COMPOSE_FILE" down --volumes --remove-orphans > /dev/null 2>&1
  # Запускаем новые
  docker-compose -f "$TEST_COMPOSE_FILE" up -d --build
  if [ $? -ne 0 ]; then
    log_message "${RED}Не удалось запустить тестовое окружение Jira.${NC}"
    stop_test_jira # Попытка очистки
    exit 1
  fi

  log_message "${YELLOW}Ожидание готовности Jira (${JIRA_CONTAINER_NAME}). Это может занять несколько минут...${NC}"
  # Используем docker wait с healthcheck статусом
  local start_time=$(date +%s)
  local timeout=300 # 5 минут таймаут ожидания
  local interval=10 # Интервал проверки

  while true; do
      local current_time=$(date +%s)
      local elapsed_time=$((current_time - start_time))

      if [ $elapsed_time -ge $timeout ]; then
          log_message "${RED}Таймаут ожидания (${timeout}с) готовности Jira (${JIRA_CONTAINER_NAME}).${NC}"
          stop_test_jira
          exit 1
      fi

      local health_status=$(docker inspect --format='{{json .State.Health.Status}}' "$JIRA_CONTAINER_NAME" 2>/dev/null | tr -d '"')

      if [ "$health_status" == "healthy" ]; then
          log_message "${GREEN}Jira (${JIRA_CONTAINER_NAME}) готова!${NC}"
          break
      elif [ "$health_status" == "unhealthy" ]; then
          log_message "${RED}Jira (${JIRA_CONTAINER_NAME}) сообщила о нездоровом состоянии.${NC}"
          docker logs "$JIRA_CONTAINER_NAME" # Выводим логи для диагностики
          stop_test_jira
          exit 1
      else
          log_message "${YELLOW}Jira (${JIRA_CONTAINER_NAME}) еще запускается (статус: ${health_status:-'неизвестно'})... Ожидание ${interval}с...${NC}"
          sleep $interval
      fi
  done

  log_message "${GREEN}Тестовое окружение Jira успешно запущено.${NC}"
}

# Функция для остановки и очистки тестового окружения Jira
stop_test_jira() {
  log_message "${YELLOW}Остановка и очистка тестового окружения Jira ($TEST_COMPOSE_FILE)...${NC}"
  docker-compose -f "$TEST_COMPOSE_FILE" down --volumes --remove-orphans
  log_message "${GREEN}Тестовое окружение Jira остановлено и очищено.${NC}"
}

# --- Управление тестовым окружением Docker --- END

# --- Функция очистки при выходе --- START
cleanup() {
  log_message "${YELLOW}Выполнение очистки перед выходом...${NC}"
  stop_test_jira
}
# Устанавливаем ловушку для выполнения cleanup при выходе (нормальном или по ошибке)
trap cleanup EXIT
# --- Функция очистки при выходе --- END

# --- Активация виртуального окружения --- START
# Проверяем наличие директории .venv и файла активации
VENV_ACTIVATE=".venv/bin/activate"
if [ -f "$VENV_ACTIVATE" ]; then
    log_message "${YELLOW}Активация виртуального окружения .venv...${NC}"
    source "$VENV_ACTIVATE"
else
    log_message "${RED}Файл активации виртуального окружения $VENV_ACTIVATE не найден.${NC}"
    log_message "${YELLOW}Пожалуйста, убедитесь, что зависимости установлены (например, с помощью 'uv sync') перед запуском скрипта.${NC}"
    exit 1
fi
# --- Активация виртуального окружения --- END

# Обработка аргументов командной строки
TEST_TYPE="all"      # По умолчанию запускаем все тесты
VERBOSITY="-v"       # Уровень детализации вывода
RUN_WRITE_TESTS=false # По умолчанию не запускаем тесты, изменяющие данные
MARKER_EXPRESSION="" # Выражение для фильтрации тестов по маркерам
# Новый флаг для запуска тестов в Docker
RUN_IN_DOCKER=true   # По умолчанию запускаем в Docker

# Справка по использованию
show_help() {
  echo "Использование: $0 [опции]"
  echo "Опции:"
  echo "  --unit        Запустить только юнит-тесты (маркер 'unit')"
  echo "  --integration Запустить интеграционные тесты (маркер 'integration', требуют окружения)"
  # echo "  --real-data   Запустить тесты с реальными данными Atlassian (маркер 'real_data')" # Скрыто, т.к. теперь есть --docker
  echo "  --all         Запустить все тесты (по умолчанию)"
  echo "  --write-tests Включить тесты, изменяющие данные (для integration, маркер 'write')"
  echo "  --no-docker   Запустить тесты локально (без запуска Docker контейнеров)"
  echo "  -m <expr>     Запустить тесты, соответствующие выражению маркера (например, 'unit and not slow')"
  echo "  --quiet       Минимальный вывод (-q)"
  echo "  --verbose     Подробный вывод (-vv)"
  echo "  -h, --help    Показать эту справку"
  exit 0
}

# Разбор аргументов командной строки
while [[ $# -gt 0 ]]; do
  case $1 in
    --unit)
      MARKER_EXPRESSION="unit"
      shift
      ;;
    --integration)
      MARKER_EXPRESSION="integration" # Интеграционные тесты теперь требуют Docker или локальной настройки
      shift
      ;;
    # --real-data) # Скрыто
    #   MARKER_EXPRESSION="real_data"
    #   shift
    #   ;;
    --all)
      MARKER_EXPRESSION="" # Пустое выражение означает запуск всех тестов
      shift
      ;;
    --write-tests)
      RUN_WRITE_TESTS=true
      shift
      ;;
    --no-docker)
      RUN_IN_DOCKER=false
      shift
      ;;
    -m)
      MARKER_EXPRESSION="$2"
      shift 2
      ;;
    --quiet)
      VERBOSITY="-q"
      shift
      ;;
    --verbose)
      VERBOSITY="-vv"
      shift
      ;;
    -h|--help)
      show_help
      ;;
    *)
      echo "Неизвестная опция: $1"
      echo "Используйте --help для получения справки"
      exit 1
      ;;
  esac
done

# Проверка наличия файла .env
if [ ! -f .env ]; then
    log_message "${RED}Файл .env не найден. Он необходим для запуска тестов.${NC}"
    log_message "${YELLOW}Пожалуйста, скопируйте .env.example в .env и заполните его.${NC}"
    # Добавим проверку на наличие .env.example
    if [ ! -f .env.example ]; then
        log_message "${RED}Файл .env.example также не найден. Не могу создать пример .env.${NC}"
        exit 1
    fi
    cp .env.example .env
    log_message "${GREEN}Файл .env создан из .env.example. Отредактируйте его и запустите скрипт снова.${NC}"
    # Важно: Убедитесь, что JIRA_URL указывает на http://jira-test-atlassian:8080 если используете --docker
    # или на ваш реальный URL, если используете --no-docker.
    # Также убедитесь, что JIRA_LICENSE_KEY и параметры БД (POSTGRES_*) заданы для Docker режима.
    exit 1
fi

# Загрузка переменных окружения из .env файла
# Docker Compose также автоматически подхватит .env из текущей директории
log_message "${YELLOW}Загрузка переменных окружения из файла .env...${NC}"
set -a # автоматически экспортировать переменные
source .env
set +a

# Проверка установленного pytest
# Теперь pytest должен быть доступен из активированного venv
if ! command -v pytest &> /dev/null; then
    log_message "${RED}Команда pytest не найдена даже после попытки активации .venv.${NC}"
    log_message "${YELLOW}Убедитесь, что pytest установлен в виртуальном окружении .venv.${NC}"
    exit 1
fi

# --- Запуск/Остановка Docker окружения (если нужно) ---
if [ "$RUN_IN_DOCKER" = true ]; then
  log_message "${YELLOW}Запуск тестов в режиме Docker.${NC}"
  # Проверка наличия compose файла
  if [ ! -f "$TEST_COMPOSE_FILE" ]; then
      log_message "${RED}Файл $TEST_COMPOSE_FILE не найден. Невозможно запустить тестовое окружение.${NC}"
      exit 1
  fi
  # Проверка/создание сети
  ensure_docker_network
  # Запуск контейнеров
  start_test_jira
  log_message "${GREEN}Тестовое окружение Docker готово.${NC}"
  # Важно: Убедитесь, что JIRA_URL в .env указывает на http://jira-test-atlassian:8080
  # и JIRA_USERNAME/JIRA_API_TOKEN соответствуют админу, созданному в контейнере
  log_message "${YELLOW}Убедитесь, что JIRA_URL, JIRA_USERNAME, JIRA_API_TOKEN в .env настроены для контейнера ${JIRA_CONTAINER_NAME} (URL: http://${JIRA_CONTAINER_NAME}:8080).${NC}"
else
  log_message "${YELLOW}Запуск тестов в локальном режиме (--no-docker). Убедитесь, что Atlassian сервисы доступны по URL из .env.${NC}"
fi
# --- Конец Запуск/Остановка Docker окружения ---

# Формирование команды pytest
PYTEST_CMD="pytest -x $VERBOSITY" # -x: остановить после первой ошибки

# Фильтрация по маркерам (упрощенная логика, т.к. real_data теперь часть integration)
FINAL_MARKER=""
if [ -n "$MARKER_EXPRESSION" ]; then
    FINAL_MARKER="$MARKER_EXPRESSION"
fi

# Обработка --write-tests
if [ "$RUN_WRITE_TESTS" = true ]; then
    # Если включены write тесты, добавляем маркер 'write' ИЛИ запускаем всё, если маркер не задан
    log_message "${RED}ВНИМАНИЕ: Будут запущены тесты, изменяющие данные (маркер 'write')!${NC}"
    log_message "${RED}Цель: ${YELLOW}$( [ "$RUN_IN_DOCKER" = true ] && echo "Тестовый Docker контейнер" || echo "Локальная/Реальная система (по JIRA_URL)" )${NC}"
    log_message "${RED}Нажмите Ctrl+C сейчас, чтобы отменить, или подождите 5 секунд для продолжения...${NC}"
    sleep 5
    if [ -n "$FINAL_MARKER" ]; then
        FINAL_MARKER="($FINAL_MARKER) and write" # Добавляем к существующему маркеру
    else
        # Если маркер не был задан (--all или не указан), write-тесты запускаются без доп. маркеров
        : # Ничего не делаем, PYTEST_CMD без -m запустит все
    fi
else
    # Если write тесты не включены, исключаем их
    if [ -n "$FINAL_MARKER" ]; then
        FINAL_MARKER="($FINAL_MARKER) and not write"
    else
        FINAL_MARKER="not write" # Исключаем write из всех тестов
    fi
fi

# Добавляем маркер к команде, если он сформирован
if [ -n "$FINAL_MARKER" ]; then
    PYTEST_CMD="$PYTEST_CMD -m \"$FINAL_MARKER\""
fi

# Добавляем путь к тестам
PYTEST_CMD="$PYTEST_CMD tests/"

log_message "${YELLOW}Запуск команды: $PYTEST_CMD${NC}"

# Выполнение pytest
eval $PYTEST_CMD
PYTEST_EXIT_CODE=$? # Сохраняем код выхода pytest

# Проверка результата
if [ $PYTEST_EXIT_CODE -eq 0 ]; then
  log_message "${GREEN}Тесты успешно пройдены!${NC}"
  exit 0
else
  log_message "${RED}Тесты не пройдены (код выхода: $PYTEST_EXIT_CODE).${NC}"
  exit $PYTEST_EXIT_CODE # Выходим с кодом ошибки pytest
fi

# Ловушка trap выполнит cleanup автоматически при выходе 