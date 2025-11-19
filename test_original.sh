#!/bin/bash
# 원본 파일 테스트 스크립트

echo "=========================================="
echo "원본 파일 SMS 테스트"
echo "=========================================="

curl -X POST "https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp" \
  -H "Content-Type: application/json" \
  -d '{
    "mode": "ars_data_add",
    "terminal_id": "05532206",
    "request_type": "SMS",
    "cc_name": "홍길동",
    "phone_no": "01024020684",
    "card_no": "1234567890123456",
    "expire_date": "2512",
    "install_month": "00",
    "orders": [
      {
        "order_no": "TEST_ORIG_'$(date +%s)'",
        "amount": 5000,
        "cc_pord_desc": "테스트"
      }
    ]
  }' | python -m json.tool 2>&1

echo ""
echo "=========================================="
echo "결과 확인 완료"
echo "=========================================="
