#!/bin/bash

OUTPUT="result.txt"
> "$OUTPUT"

# Список расширений, которые нужно игнорировать (через | )
EXCLUDE_EXTENSIONS="jar|zip|gz|tar|exe|png|jpg|pdf"

find . -type f | while read -r file; do
    # 1. Пропускаем сам скрипт и выходной файл
    if [[ "$file" == "./$OUTPUT" || "$file" == "./$(basename "$0")" ]]; then
        continue
    fi

    # 2. Пропускаем по расширению (регистронезависимо)
    if [[ "$file" =~ \.($EXCLUDE_EXTENSIONS)$ ]]; then
        echo "Игнорирую (запрещенное расширение): $file"
        continue
    fi

    # 3. Проверяем mime-тип (на всякий случай для файлов без расширения)
    if file --mime "$file" | grep -q "text"; then
        echo -e "\n--- Следующий файл по пути: $file ---\n" >> "$OUTPUT"
        cat "$file" >> "$OUTPUT"
        echo -e "\n" >> "$OUTPUT"
    else
        echo "Пропуск бинарного файла: $file"
    fi
done

echo "---"
echo "Готово! Все тексты собраны в $OUTPUT"