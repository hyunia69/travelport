@echo off
chcp 65001 > nul
echo ============================================
echo KICC ARS SMS/MMS 자동 구분 테스트
echo ============================================
echo.

echo [테스트 1] SMS 전송 (짧은 메시지)
echo 메시지: "홍길동님께서 주문하신 상품에 대한 결제 안내 메시지입니다"
curl -X POST "https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp" ^
  -H "Content-Type: application/json" ^
  -d "{\"mode\":\"ars_data_add\",\"terminal_id\":\"05532206\",\"request_type\":\"SMS\",\"cc_name\":\"홍길동\",\"phone_no\":\"01024020684\",\"card_no\":\"1234567890123456\",\"expire_date\":\"2512\",\"install_month\":\"00\",\"orders\":[{\"order_no\":\"TEST_SMS_%RANDOM%\",\"amount\":5000,\"cc_pord_desc\":\"테스트 상품\"}]}"
echo.
echo.

echo [테스트 2] MMS 전송 (긴 메시지 - 80자 이상)
echo 메시지: "홍길동님께서 주문하신 프리미엄 테스트 상품에 대한 결제 안내 메시지입니다. 결제 정보를 확인하시고 안내된 번호로 전화주시기 바랍니다."
curl -X POST "https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp" ^
  -H "Content-Type: application/json" ^
  -d "{\"mode\":\"ars_data_add\",\"terminal_id\":\"05532206\",\"request_type\":\"SMS\",\"cc_name\":\"홍길동님께서 주문하신 프리미엄 테스트 상품에 대한 결제 안내 메시지입니다\",\"phone_no\":\"01024020684\",\"card_no\":\"1234567890123456\",\"expire_date\":\"2512\",\"install_month\":\"00\",\"mms_subject\":\"주문 결제 안내\",\"orders\":[{\"order_no\":\"TEST_MMS_%RANDOM%\",\"amount\":5000,\"cc_pord_desc\":\"프리미엄 테스트 상품\"}]}"
echo.
echo.

echo [테스트 3] MMS 전송 (사용자 지정 제목)
curl -X POST "https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp" ^
  -H "Content-Type: application/json" ^
  -d "{\"mode\":\"ars_data_add\",\"terminal_id\":\"05532206\",\"request_type\":\"SMS\",\"cc_name\":\"홍길동님께서 주문하신 프리미엄 VIP 상품에 대한 특별 결제 안내 메시지입니다\",\"phone_no\":\"01024020684\",\"card_no\":\"1234567890123456\",\"expire_date\":\"2512\",\"install_month\":\"00\",\"mms_subject\":\"[VIP] 특별 결제 안내\",\"orders\":[{\"order_no\":\"TEST_MMS_VIP_%RANDOM%\",\"amount\":10000,\"cc_pord_desc\":\"VIP 프리미엄 상품\"}]}"
echo.
echo.

echo ============================================
echo 테스트 완료
echo ============================================
pause
