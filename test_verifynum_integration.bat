@echo off
chcp 65001 > nul
echo ========================================
echo 인증번호 생성 통합 테스트
echo ========================================
echo.

set API_URL=https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp

echo.
echo [테스트 1] ARS 타입 - 인증번호 생성 (SMS 발송 없음)
echo ========================================
curl -X POST "%API_URL%" ^
  -H "Content-Type: application/json" ^
  -d "{\"mode\":\"ars_data_add\",\"terminal_id\":\"05532206\",\"request_type\":\"ARS\",\"cc_name\":\"홍길동\",\"phone_no\":\"01024020684\",\"card_no\":\"1234567890123456\",\"expire_date\":\"2512\",\"install_month\":\"00\",\"orders\":[{\"order_no\":\"ARS_TEST_%RANDOM%\",\"amount\":1000,\"cc_pord_desc\":\"ARS 테스트 상품\"}]}"

echo.
echo.
echo [테스트 2] SMS 타입 - 인증번호 생성 + SMS 발송 (배치당 1회)
echo ========================================
curl -X POST "%API_URL%" ^
  -H "Content-Type: application/json" ^
  -d "{\"mode\":\"ars_data_add\",\"terminal_id\":\"05532206\",\"request_type\":\"SMS\",\"cc_name\":\"김철수\",\"phone_no\":\"01024020684\",\"card_no\":\"1234567890123456\",\"expire_date\":\"2512\",\"install_month\":\"00\",\"orders\":[{\"order_no\":\"SMS_TEST_%RANDOM%\",\"amount\":2000,\"cc_pord_desc\":\"SMS 테스트 상품 1\"},{\"order_no\":\"SMS_TEST_%RANDOM%\",\"amount\":3000,\"cc_pord_desc\":\"SMS 테스트 상품 2\"}]}"

echo.
echo.
echo [테스트 3] KTK 타입 - MMS 발송 (긴 메시지)
echo ========================================
curl -X POST "%API_URL%" ^
  -H "Content-Type: application/json" ^
  -d "{\"mode\":\"ars_data_add\",\"terminal_id\":\"05532206\",\"request_type\":\"KTK\",\"cc_name\":\"이영희\",\"phone_no\":\"01024020684\",\"card_no\":\"1234567890123456\",\"expire_date\":\"2512\",\"install_month\":\"00\",\"sms_message\":\"안녕하세요 고객님, 프리미엄 결제를 도와드리겠습니다. 아래 인증번호로 전화해주세요.\",\"mms_subject\":\"프리미엄 결제 안내\",\"orders\":[{\"order_no\":\"KTK_TEST_%RANDOM%\",\"amount\":5000,\"cc_pord_desc\":\"KTK 프리미엄 상품\"}]}"

echo.
echo.
echo [테스트 4] 배치 주문 (3건) - 모든 주문에 동일한 인증번호
echo ========================================
curl -X POST "%API_URL%" ^
  -H "Content-Type: application/json" ^
  -d "{\"mode\":\"ars_data_add\",\"terminal_id\":\"05532206\",\"request_type\":\"SMS\",\"cc_name\":\"박민수\",\"phone_no\":\"01024020684\",\"card_no\":\"1234567890123456\",\"expire_date\":\"2512\",\"install_month\":\"00\",\"orders\":[{\"order_no\":\"BATCH_TEST_%RANDOM%_1\",\"amount\":1000,\"cc_pord_desc\":\"배치 상품 1\"},{\"order_no\":\"BATCH_TEST_%RANDOM%_2\",\"amount\":2000,\"cc_pord_desc\":\"배치 상품 2\"},{\"order_no\":\"BATCH_TEST_%RANDOM%_3\",\"amount\":3000,\"cc_pord_desc\":\"배치 상품 3\"}]}"

echo.
echo.
echo ========================================
echo 모든 테스트 완료
echo ========================================
echo.
echo 데이터베이스 확인:
echo 1. KICC_SHOP_ORDER 테이블에서 auth_no 필드 확인
echo 2. 배치 내 모든 주문건이 동일한 auth_no를 가지는지 확인
echo 3. ARS 타입도 auth_no가 저장되어 있는지 확인
echo 4. SMS/KTK 타입만 em_smt_tran/em_mmt_tran에 등록되었는지 확인
echo 5. mt_refkey가 "terminal_id@BATCH" 형식인지 확인
echo.
pause
