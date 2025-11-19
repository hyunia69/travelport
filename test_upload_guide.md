# MMS 기능 추가 완료 - 업로드 및 테스트 가이드

## 수정 완료 사항

### 1. 변경 파일
- `dev/db/kicc_ars_order_v3_batch.asp` (23K → 25K)

### 2. 추가된 기능
- **자동 SMS/MMS 판별**: 메시지 길이가 80자 이상이면 자동으로 MMS 전송
- **MMS 제목 설정**: `mms_subject` 파라미터로 MMS 제목 지정 가능 (기본값: "주문 결제 안내")

### 3. 변경 사항 요약
```diff
+ mms_subject 변수 추가
+ mms_subject 파라미터 추출
+ msgLength, useMMS 변수 추가
+ 메시지 길이 체크 로직 (80자 기준)
+ MMS 전송 코드 (em_mmt_tran 테이블)
+ SMS/MMS 분기 처리
```

## 서버 업로드 방법

### 방법 1: FTP/SFTP 업로드
1. FTP 클라이언트로 서버 접속
2. `dev/db/kicc_ars_order_v3_batch.asp` 파일 업로드
3. 서버 경로: `/ars/kicc/dev/db/`

### 방법 2: Git 배포
```bash
# 로컬에서 커밋
git add dev/db/kicc_ars_order_v3_batch.asp
git commit -m "Add MMS support with 80-character auto-detection"
git push origin master

# 서버에서 pull
# (서버 SSH 접속 후)
cd /path/to/kicc
git pull origin master
```

### 방법 3: 수동 복사
```bash
# 로컬 파일을 서버로 복사 (scp 사용 예시)
scp dev/db/kicc_ars_order_v3_batch.asp user@server:/path/to/kicc/dev/db/
```

## 테스트 스크립트

### 테스트 1: SMS 전송 (짧은 메시지 - 80자 미만)
```bash
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
        "order_no": "TEST_SMS_'$(date +%s)'",
        "amount": 5000,
        "cc_pord_desc": "테스트상품"
      }
    ]
  }'
```

**예상 결과**: em_smt_tran 테이블에 SMS 등록

### 테스트 2: MMS 전송 (긴 메시지 - 80자 이상)
```bash
curl -X POST "https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp" \
  -H "Content-Type: application/json" \
  -d '{
    "mode": "ars_data_add",
    "terminal_id": "05532206",
    "request_type": "SMS",
    "cc_name": "홍길동님께서 주문하신 프리미엄 VIP 상품에 대한 특별 결제 안내 메시지입니다. 고객센터로 연락 부탁드립니다",
    "phone_no": "01024020684",
    "card_no": "1234567890123456",
    "expire_date": "2512",
    "install_month": "00",
    "mms_subject": "주문 결제 안내",
    "orders": [
      {
        "order_no": "TEST_MMS_'$(date +%s)'",
        "amount": 10000,
        "cc_pord_desc": "프리미엄 상품"
      }
    ]
  }'
```

**예상 결과**: em_mmt_tran 테이블에 MMS 등록

### 테스트 3: MMS 전송 (사용자 지정 제목)
```bash
curl -X POST "https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp" \
  -H "Content-Type: application/json" \
  -d '{
    "mode": "ars_data_add",
    "terminal_id": "05532206",
    "request_type": "SMS",
    "cc_name": "홍길동님께서 주문하신 최고급 VIP 프리미엄 상품에 대한 결제 안내입니다. 빠른 시일 내에 연락 부탁드립니다",
    "phone_no": "01024020684",
    "card_no": "1234567890123456",
    "expire_date": "2512",
    "install_month": "00",
    "mms_subject": "[VIP] 특별 결제 안내",
    "orders": [
      {
        "order_no": "TEST_MMS_VIP_'$(date +%s)'",
        "amount": 50000,
        "cc_pord_desc": "VIP 프리미엄 상품"
      }
    ]
  }'
```

**예상 결과**: em_mmt_tran 테이블에 MMS 등록, subject = "[VIP] 특별 결제 안내"

## 검증 방법

### 1. SMS 전송 확인
```sql
-- em_smt_tran 테이블 확인
SELECT TOP 10
  mt_refkey,
  content,
  recipient_num,
  date_client_req,
  msg_status
FROM em_smt_tran
WHERE rs_id = 'KICC'
ORDER BY date_client_req DESC
```

### 2. MMS 전송 확인
```sql
-- em_mmt_tran 테이블 확인
SELECT TOP 10
  mt_refkey,
  subject,
  content,
  recipient_num,
  date_client_req,
  msg_status
FROM em_mmt_tran
WHERE rs_id = 'KICC'
ORDER BY date_client_req DESC
```

### 3. 메시지 길이 확인
```sql
-- 메시지 길이별 분포 확인
SELECT
  CASE
    WHEN LEN(content) < 80 THEN 'SMS (< 80자)'
    ELSE 'MMS (>= 80자)'
  END AS 메시지타입,
  COUNT(*) AS 건수,
  AVG(LEN(content)) AS 평균길이
FROM (
  SELECT content FROM em_smt_tran WHERE rs_id = 'KICC'
  UNION ALL
  SELECT content FROM em_mmt_tran WHERE rs_id = 'KICC'
) AS all_messages
GROUP BY
  CASE
    WHEN LEN(content) < 80 THEN 'SMS (< 80자)'
    ELSE 'MMS (>= 80자)'
  END
```

## 트러블슈팅

### 문제 1: 500 에러 발생
- **원인**: ASP 파일 문법 오류 또는 데이터베이스 연결 문제
- **해결**: IIS 로그 확인 (`C:\inetpub\logs\LogFiles\`)

### 문제 2: MMS가 SMS로 전송됨
- **원인**: 메시지 길이가 80자 미만
- **해결**: 메시지 내용 확인 (한글 1자 = 1문자로 계산)

### 문제 3: 데이터베이스 테이블 접근 오류
- **원인**: em_mmt_tran 테이블 권한 문제
- **해결**: 데이터베이스 연결 계정의 em_mmt_tran 테이블 INSERT 권한 확인

```sql
-- 권한 확인
USE imds
GO
SELECT * FROM sys.database_permissions
WHERE grantee_principal_id = USER_ID('imds')
```

## 롤백 방법

문제 발생 시 원본으로 복구:

```bash
# 로컬에서
git restore dev/db/kicc_ars_order_v3_batch.asp

# 또는 백업 파일 사용
cp dev/db/kicc_ars_order_v3_batch.asp.backup dev/db/kicc_ars_order_v3_batch.asp
```

## 주의사항

1. **서버 업로드 전 백업**: 서버의 기존 파일을 백업해두세요
2. **테스트 순서**: 짧은 메시지(SMS) → 긴 메시지(MMS) 순서로 테스트
3. **데이터베이스 확인**: 두 테이블 모두에 데이터가 정상적으로 INSERT되는지 확인
4. **로그 모니터링**: IIS 로그와 애플리케이션 로그를 실시간으로 모니터링
