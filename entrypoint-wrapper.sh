#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "--- Custom Jira Entrypoint Wrapper ---"

JIRA_HOME="/var/atlassian/application-data/jira"
LICENSE_SOURCE="/tmp/jira-license.key"
LICENSE_DEST="$JIRA_HOME/jira-license.key"

if [ -f "$LICENSE_SOURCE" ]; then
  echo "Found license file at $LICENSE_SOURCE. Attempting to copy to Jira home ($JIRA_HOME)..."
  # Создаем директорию Jira Home, если она еще не существует
  mkdir -p "$JIRA_HOME"
  # Копируем файл
  cp "$LICENSE_SOURCE" "$LICENSE_DEST"
  # Устанавливаем права доступа
  chmod 600 "$LICENSE_DEST"
  # Проверяем, скопировался ли файл
  if [ -f "$LICENSE_DEST" ]; then
     echo "License file successfully copied to $LICENSE_DEST."
  else
     echo "ERROR: Failed to copy license file to $LICENSE_DEST!" >&2
     # Решаем, останавливать ли запуск, если копирование не удалось
     # exit 1 # Раскомментировать, если это критично
  fi
else
  echo "WARNING: License file $LICENSE_SOURCE not found. Jira might require manual activation." >&2
fi

echo "Executing original Jira entrypoint (/entrypoint.py) with args: $@"
echo "--- End Custom Wrapper ---"

# Запускаем оригинальный entrypoint скрипт Jira, передавая ему все аргументы,
# которые могли быть переданы нашему wrapper-скрипту (например, из CMD Dockerfile)
# Обычно оригинальный entrypoint сам вызывает start-jira.sh
exec /entrypoint.py "$@" 