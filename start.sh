#!/bin/bash

# Скрипт для сборки и запуска проекта mcp-atlassian в Docker

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Печать сообщения с датой и временем
log_message() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Проверка установки Docker
if ! command -v docker &> /dev/null; then
  log_message "${RED}Docker не установлен. Пожалуйста, установите Docker перед запуском скрипта.${NC}"
  exit 1
fi

# Создание сети Docker, если она не существует
if ! docker network inspect rnd-network &> /dev/null; then
  log_message "${YELLOW}Создание сети Docker 'rnd-network'...${NC}"
  docker network create --driver bridge rnd-network
  if [ $? -eq 0 ]; then
    log_message "${GREEN}Сеть Docker 'rnd-network' успешно создана.${NC}"
  else
    log_message "${RED}Не удалось создать сеть Docker 'rnd-network'.${NC}"
    exit 1
  fi
fi

# Проверка наличия .env файла
if [ ! -f .env ]; then
  log_message "${YELLOW}Файл .env не найден. Создание примера .env файла...${NC}"
  cat > .env << EOL
# Настройки Confluence
CONFLUENCE_URL=https://your-company.atlassian.net/wiki
CONFLUENCE_USERNAME=your.email@company.com
CONFLUENCE_API_TOKEN=your_confluence_api_token
CONFLUENCE_SPACES_FILTER=DEV,TEAM,DOC

# Настройки Jira
JIRA_URL=https://your-company.atlassian.net
JIRA_USERNAME=your.email@company.com
JIRA_API_TOKEN=your_jira_api_token
JIRA_PROJECTS_FILTER=PROJ,DEV,SUPPORT

# Общие настройки
READ_ONLY_MODE=true
MCP_VERBOSE=true
EOL
  log_message "${YELLOW}Создан пример файла .env. Пожалуйста, отредактируйте его с вашими учетными данными.${NC}"
  log_message "${YELLOW}Для продолжения нужно заполнить файл .env. После этого запустите скрипт снова.${NC}"
  exit 1
fi

# Обновление версии в файле backend_version
current_version=$(grep 'version = ' pyproject.toml | awk -F'"' '{print $2}')
echo "$current_version" > backend_version
log_message "${GREEN}Версия $current_version сохранена в файле backend_version${NC}"

# Обновление записи в CHANGELOG.md, если там нет текущей версии
if ! grep -q "\[${current_version}\]" CHANGELOG.md; then
  log_message "${YELLOW}Добавление информации о текущей версии в CHANGELOG.md...${NC}"
  
  # Получение текущей даты в формате YYYY-MM-DD
  today=$(date +'%Y-%m-%d')
  
  # Вставка новой версии после строки [Unreleased]
  sed -i.bak "/## \[Unreleased\]/a\\
\\
## [${current_version}] - ${today}\\
\\
### Changed\\
- Обновлен скрипт сборки и запуска Docker контейнеров\\
- Добавлен Docker Compose для управления контейнерами\\
\\
" CHANGELOG.md
  
  rm CHANGELOG.md.bak
  log_message "${GREEN}CHANGELOG.md обновлен.${NC}"
fi

# Создание docker-compose.yml файла
log_message "${YELLOW}Создание файла docker-compose.yml...${NC}"
cat > docker-compose.yml << EOL
version: '3.8'

services:
  mcp-atlassian:
    image: ghcr.io/sooperset/mcp-atlassian:latest
    container_name: mcp-atlassian
    build:
      context: .
      dockerfile: Dockerfile
    env_file:
      - .env
    networks:
      - rnd-network
    ports:
      - "9000:9000"
    entrypoint: ["mcp-atlassian", "--transport", "sse", "--port", "9000"]

networks:
  rnd-network:
    external: true
EOL
log_message "${GREEN}Файл docker-compose.yml создан.${NC}"

# Запуск тестов
log_message "${YELLOW}Запуск тестов...${NC}"
docker build -t mcp-atlassian-test -f Dockerfile . && \
docker run --rm --env-file .env mcp-atlassian-test pytest -xvs tests/unit

if [ $? -eq 0 ]; then
  log_message "${GREEN}Тесты успешно пройдены.${NC}"
else
  log_message "${RED}Тесты не пройдены. Проверьте логи для получения дополнительной информации.${NC}"
  log_message "${YELLOW}Продолжение сборки несмотря на ошибки тестов...${NC}"
fi

# Сборка и запуск с помощью Docker Compose
log_message "${YELLOW}Сборка и запуск Docker контейнеров...${NC}"
docker-compose build
docker-compose up -d

# Проверка статуса контейнера
if [ $? -eq 0 ]; then
  log_message "${GREEN}Docker контейнеры успешно запущены.${NC}"
  log_message "${GREEN}Сервер доступен по адресу: http://localhost:9000/sse${NC}"
  
  # Проверка логов контейнера
  log_message "${YELLOW}Вывод логов контейнера:${NC}"
  docker-compose logs mcp-atlassian
  
  log_message "${GREEN}Проект успешно собран и запущен!${NC}"
  log_message "${YELLOW}Для остановки контейнеров выполните: docker-compose down${NC}"
else
  log_message "${RED}Не удалось запустить Docker контейнеры. Проверьте логи для получения дополнительной информации.${NC}"
  exit 1
fi 