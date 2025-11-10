#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
YAML 파일에서 에러 코드 0014, 0015 제거 스크립트
"""

import re

yaml_file = "D:/dasam/travelport/code/kicc/api-docs/swagger/kicc_ars_api_v3_batch.yaml"

# 파일 읽기
with open(yaml_file, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. 에러 코드 테이블에서 0014, 0015 행 삭제 (라인 53-54)
content = re.sub(
    r'    \| \*\*0014\*\* \| .+?\n',
    '',
    content
)
content = re.sub(
    r'    \| \*\*0015\*\* \| .+?\n',
    '',
    content
)

# 2. examples 섹션에서 error_0014, error_0015 전체 블록 삭제
# error_0014 블록 삭제 (520-531행)
content = re.sub(
    r'\n                error_0014:.*?message: "카드번호형식오류"\n',
    '',
    content,
    flags=re.DOTALL
)

# error_0015 블록 삭제 (533-544행)
content = re.sub(
    r'\n                error_0015:.*?message: "카드번호복호화실패"\n',
    '',
    content,
    flags=re.DOTALL
)

# 3. x-error-codes 섹션에서 0014, 0015 전체 블록 삭제
content = re.sub(
    r'\n  - code: "0014".*?encryption_related: true\n',
    '',
    content,
    flags=re.DOTALL
)

content = re.sub(
    r'\n  - code: "0015".*?encryption_related: true\n',
    '',
    content,
    flags=re.DOTALL
)

# 파일 쓰기
with open(yaml_file, 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ 에러 코드 0014, 0015가 성공적으로 삭제되었습니다.")
print("삭제된 위치:")
print("  1. 에러 코드 테이블 (description 섹션)")
print("  2. examples 섹션 (error_0014, error_0015)")
print("  3. x-error-codes 섹션")
