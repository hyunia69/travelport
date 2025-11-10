# CLAUDE.md

이 파일은 Claude Code(claude.ai/code)가 이 저장소의 코드 작업 시 참고하는 가이드입니다.

## 프로젝트 개요

**KICC ARS 배치 결제 주문 API** - ARS(자동응답시스템), SMS, 카카오톡 결제 방식을 위한 배치 주문 처리 시스템입니다. JSON orders 배열을 사용하여 단일 API 호출로 여러 건의 결제 주문을 동시에 생성할 수 있습니다.

**핵심 기술**: Classic ASP + SQL Server
**주요 언어**: 한국어(UTF-8)
**데이터베이스**: SQL Server (arspg_web, imds 카탈로그)
**운영 서버**: https://www.arspg.co.kr/ars/kicc/

## 개발 명령어

### Swagger UI 문서 서버 시작
```bash
# Windows Batch
cd api-docs/swagger
start-local-server.bat

# PowerShell
cd api-docs/swagger
.\start-local-server.ps1

# Python (크로스 플랫폼)
cd api-docs/swagger
python -m http.server 8000
# 접속: http://localhost:8000/index.html
```

### Swagger 문서 업데이트
```bash
cd api-docs/swagger
python update_batch.py
```

## 아키텍처 구조

### 디렉토리 구조
```
kicc/
├── dev/db/                      # 개발용 ASP 엔드포인트
│   └── kicc_ars_order_v3_batch_json.asp
├── api-docs/
│   ├── swagger/                 # OpenAPI 3.0 명세 및 Swagger UI
│   │   ├── index.html
│   │   ├── kicc_ars_api_v3_batch.yaml
│   │   └── update_batch.py
│   └── postman/                 # Postman 테스트 컬렉션
└── docs/                        # 추가 문서
```

### 핵심 API 엔드포인트

**파일**: `dev/db/kicc_ars_order_v3_batch_json.asp`
- **Content-Type**: `application/json`
- **배치 형식**: orders 배열
- **사용처**: 웹/모바일 앱, REST API 클라이언트

### 배치 주문 처리 로직

이 파일이 전체 배치 주문 처리 로직을 담당합니다:

#### 1. 요청 수신 및 파라미터 파싱

**JSON 요청 처리**:
- JSON 바디 읽기: `ReadRequestBody()`
- 공통 파라미터 추출: `ExtractJsonString()`
- orders 배열 파싱: `ParseJsonOrders()`

#### 2. 배치 파라미터 처리 로직
**배치 가능 파라미터** (각 주문별로 다른 값):
- `order_no`: 주문번호
- `amount`: 결제금액 (숫자 또는 문자열)
- `cc_pord_desc`: 상품명

**공통 파라미터** (모든 주문에 동일 적용):
- **필수**: `terminal_id`, `request_type`, `cc_name`, `phone_no`, `card_no`, `expire_date`, `install_month`
- **선택**: `cc_email`

> **⚠️ 필수 파라미터 검증**:
> - `card_no` (카드번호), `expire_date` (유효기간), `install_month` (할부개월수)는 **OpenAPI 스펙과 서버 모두에서 필수**로 검증됩니다
> - Swagger UI에서 이 필드들을 비워서 전송하면 서버에서 에러 응답이 반환됩니다
> - 서버는 누락 시 에러코드 **0005** (카드번호누락), **0014** (유효기간누락), **0015** (할부개월수누락)를 반환합니다
> - **실제 운영에서는 반드시 모든 필수 값을 전달해야 합니다**


#### 3. 가맹점 정보 검증
- 저장 프로시저 호출: `sp_getKiccShopInfo`
- 파라미터: `@TERMINAL_ID`
- 반환 정보: terminal_nm, terminal_pw, ars_dnis, admin_id, admin_name
- **중요**: 배치 주문 시 1회만 조회하여 성능 최적화

#### 4. 배치 주문 처리 루프
각 주문건별로 순차 처리:
1. **중복 검증**: `KICC_SHOP_ORDER` 테이블에서 `terminal_id + order_no` 조회
2. **SMS 인증번호 생성** (SMS/KTK 타입인 경우):
   - 저장 프로시저: `sp_getKiccAuthNo`
   - 6자리 숫자 생성 (000100부터 시작)
   - SMS 발송 큐 등록 (`em_smt_tran` 테이블)
3. **주문 저장**: `KICC_SHOP_ORDER` 테이블에 INSERT
4. **결과 누적**: 성공/실패 카운트 및 메시지 누적

#### 5. 응답 생성 (JSON 형식)
```json
{
  "batch_summary": {
    "total": N,
    "success": M,
    "fail": K
  },
  "req_result": [
    {
      "order_no": "order_no1",
      "phone_no": "phone_no",
      "result_code": "결과코드",
      "message": "결과메시지"
    },
    {
      "order_no": "order_no2",
      "phone_no": "phone_no",
      "result_code": "결과코드",
      "message": "결과메시지"
    }
  ]
}
```

### 데이터베이스 아키텍처

#### 주 데이터베이스: arspg_web
- **테이블**: `KICC_SHOP_ORDER`
  - 주문 정보 저장 (order_no, terminal_id, amount, good_nm 등)
  - 고유키: `terminal_id + order_no` 조합

- **저장 프로시저**:
  - `sp_getKiccShopInfo`: 가맹점 정보 조회 (terminal_id 검증)
  - `sp_getKiccAuthNo`: SMS 인증번호 순차 생성

#### SMS 데이터베이스: imds
- **테이블**: `em_smt_tran` (SMS 발송 큐)
  - SMS 메시지 내용 및 수신번호 저장
  - 각 주문건마다 개별 SMS 발송 등록

### 배치 처리 핵심 로직

#### 부분 성공 지원
- 일부 주문이 실패(중복, 검증 오류 등)해도 성공한 주문은 정상 저장
- 각 주문건의 결과를 독립적으로 반환

#### 배치 검증
- orders 배열의 모든 항목에 필수 필드 포함 확인:
  - 각 주문에 `order_no`, `amount`, `cc_pord_desc` 필수
  - 누락 시 에러코드 0012, 0013

#### 성능 최적화
- 가맹점 정보: 배치당 1회만 조회
- 중복 체크: 주문건당 1회 SELECT 쿼리
- INSERT 작업: 주문건당 1회
- 권장 배치 크기: 1~50건

### 에러 코드 체계

주요 에러 코드:
- **0000**: 등록성공
- **0001**: 전송데이터구분오류 (mode != "ars_data_add")
- **0002**: 주문번호누락 (orders 배열 필요)
- **0003**: 가맹점터미널ID누락
- **0004**: ARS타입누락
- **0005**: 카드번호누락
- **0006**: 고객명누락
- **0007**: 상품명누락
- **0008**: 결제금액누락
- **0009**: 전화번호누락
- **0010**: 가맹점터미널ID불일치 (미등록 가맹점)
- **0011**: 거래번호중복 (terminal_id + order_no 중복)
- **0014**: 유효기간누락 (expire_date 파라미터 누락)
- **0015**: 할부개월수누락 (install_month 파라미터 누락)
- **0012**: 주문건수와 금액건수 불일치 (orders 배열 내 필수 필드 누락)
- **0013**: 주문건수와 상품명건수 불일치 (orders 배열 내 필수 필드 누락)

### 요청 타입별 처리

#### ARS 타입 (request_type=ARS)
- 전화 결제 주문 생성
- SMS 발송 없음
- 주문 정보만 데이터베이스에 저장

#### SMS/KTK 타입 (request_type=SMS 또는 KTK)
- 각 주문건마다 개별 인증번호 생성
- SMS 발송 큐에 등록
- SMS 내용: "{고객명} 님의 주문인증번호는[{인증번호}]입니다 {콜백번호} 로전화주십시오"
- 콜백번호: `02-3490-{ars_dnis}` (기본값: 02-3490-4411)

## JSON 요청 방식

### JSON 배치 주문 형식

```json
{
  "mode": "ars_data_add",
  "terminal_id": "05532206",
  "request_type": "ARS",
  "cc_name": "홍길동",
  "phone_no": "01012345678",
  "card_no": "1234567890123456",
  "expire_date": "2512",
  "install_month": "00",
  "orders": [
    {"order_no": "ORD001", "amount": 1000, "cc_pord_desc": "상품A"},
    {"order_no": "ORD002", "amount": 2000, "cc_pord_desc": "상품B"}
  ]
}
```

### JSON 파싱 제약사항

⚠️ Classic ASP의 정규식 기반 파싱으로 인한 제한:

1. **중첩 객체 미지원**
   - ❌ `{"user": {"name": "홍길동"}}` 형식 불가
   - ✅ Flat 구조만 지원

2. **특수문자 제한**
   - 문자열 값에 `"`, `'`, `{`, `}` 포함 시 파싱 오류 가능
   - 일반 한글, 영문, 숫자는 안전

3. **배열 제한**
   - orders 배열만 지원
   - 다른 배열 필드는 파싱되지 않음

4. **데이터 타입**
   - **amount는 숫자/문자열 모두 허용**
     - ✅ `"amount": 1000` (숫자)
     - ✅ `"amount": "1000"` (문자열)
   - 내부적으로 문자열로 처리되므로 두 방식 모두 동일하게 작동

### 응답 형식

**JSON 응답**:
- Content-Type: `application/json; charset=utf-8`
- 구조: `batch_summary` + `req_result` 배열

## 중요한 기술 세부사항

### 문자 인코딩
모든 ASP 파일은 UTF-8 인코딩 사용:
```asp
Response.CharSet = "utf-8"
Response.CodePage = 65001
```
ASP 파일 편집 시 반드시 UTF-8 인코딩 유지 (한글 깨짐 방지)

### CORS 설정
Swagger UI 테스트를 위한 CORS 헤더 포함:
```asp
Response.AddHeader "Access-Control-Allow-Origin", "*"
Response.AddHeader "Access-Control-Allow-Methods", "GET, POST, OPTIONS"
Response.AddHeader "Access-Control-Allow-Headers", "Content-Type"
```
⚠️ 운영 환경 배포 전 CORS 정책 검토 필요

### SQL 인젝션 주의
- 저장 프로시저 호출은 파라미터화된 쿼리 사용 (안전)
- 일부 동적 쿼리는 문자열 연결 사용:
```asp
qry = "SELECT count(order_no) cnt FROM KICC_SHOP_ORDER where terminal_id = '"& terminal_id &"' and order_no = '"& currentOrderNo &"'"
```
쿼리 수정 시 파라미터화된 Command 객체 사용 권장

### 데이터베이스 연결
- **보안**: 연결 문자열에 하드코딩된 자격 증명 포함
- **개선 필요**: 운영 환경에서는 외부 설정 파일 또는 환경 변수 사용 권장

## 테스트 전략

### Swagger UI 테스트
1. 로컬 서버 시작: `start-local-server.bat`
2. 브라우저 접속: `http://localhost:8000/index.html`
3. "Try it out" 기능으로 직접 테스트

### 주요 테스트 시나리오

#### JSON 방식 (`kicc_ars_order_v3_batch_json.asp`)
1. **JSON orders 배열 성공**: orders 배열 방식 정상 처리 (2~3건)
2. **중복 주문**: 주문번호 중복 검증 (에러코드 0011)
3. **잘못된 터미널ID**: 가맹점 검증 (에러코드 0010)
4. **빈 JSON 바디**: 빈 객체 {} 전송 시 적절한 에러 반환
5. **JSON 파싱 제약**: 중첩 객체, 특수문자 처리 확인
6. **UTF-8 한글 처리**: JSON 한글 데이터 정상 파싱
7. **SMS 타입**: 인증번호 생성 및 SMS 큐 등록 확인
8. **필수 파라미터 누락**: 유효기간/할부개월수 누락 검증 (에러코드 0014, 0015)
9. **orders 배열 필수 필드 누락**: order_no, amount, cc_pord_desc 누락 확인 (에러코드 0012, 0013)

### JSON 응답 파싱 방법

#### JavaScript 예제
```javascript
fetch(apiUrl, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    mode: 'ars_data_add',
    terminal_id: '05532206',
    request_type: 'ARS',
    cc_name: '홍길동',
    phone_no: '01012345678',
    card_no: '1234567890123456',
    expire_date: '2512',
    install_month: '00',
    orders: [
      {order_no: 'ORD001', amount: 1000, cc_pord_desc: '상품A'},
      {order_no: 'ORD002', amount: 2000, cc_pord_desc: '상품B'}
    ]
  })
})
.then(response => response.json())
.then(data => {
  // 배치 요약 정보
  const summary = data.batch_summary;
  console.log(`총 ${summary.total}건 / 성공 ${summary.success}건 / 실패 ${summary.fail}건`);

  // 각 주문건 처리
  data.req_result.forEach(result => {
    if (result.result_code === "0000") {
      console.log(`✅ 성공: ${result.order_no}`);
    } else {
      console.error(`❌ 실패: ${result.order_no} - ${result.message}`);
    }
  });
});
```

#### Python 예제
```python
import requests
import json

response = requests.post(api_url,
    headers={'Content-Type': 'application/json'},
    json={
        'mode': 'ars_data_add',
        'terminal_id': '05532206',
        'request_type': 'ARS',
        'cc_name': '홍길동',
        'phone_no': '01012345678',
        'card_no': '1234567890123456',
        'expire_date': '2512',
        'install_month': '00',
        'orders': [
            {'order_no': 'ORD001', 'amount': 1000, 'cc_pord_desc': '상품A'},
            {'order_no': 'ORD002', 'amount': 2000, 'cc_pord_desc': '상품B'}
        ]
    })

data = response.json()

# 배치 요약 정보
summary = data['batch_summary']
print(f"총 {summary['total']}건 / 성공 {summary['success']}건 / 실패 {summary['fail']}건")

# 각 주문건 처리
for result in data['req_result']:
    if result['result_code'] == '0000':
        print(f"✅ 성공: {result['order_no']}")
    else:
        print(f"❌ 실패: {result['order_no']} - {result['message']}")
```

#### PHP 예제
```php
<?php
$data = [
    'mode' => 'ars_data_add',
    'terminal_id' => '05532206',
    'request_type' => 'ARS',
    'cc_name' => '홍길동',
    'phone_no' => '01012345678',
    'card_no' => '1234567890123456',
    'expire_date' => '2512',
    'install_month' => '00',
    'orders' => [
        ['order_no' => 'ORD001', 'amount' => 1000, 'cc_pord_desc' => '상품A'],
        ['order_no' => 'ORD002', 'amount' => 2000, 'cc_pord_desc' => '상품B']
    ]
];

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $apiUrl);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$response = curl_exec($ch);
curl_close($ch);

$data = json_decode($response, true);

// 배치 요약 정보
$summary = $data['batch_summary'];
echo "총 {$summary['total']}건 / 성공 {$summary['success']}건 / 실패 {$summary['fail']}건\n";

// 각 주문건 처리
foreach ($data['req_result'] as $result) {
    if ($result['result_code'] === '0000') {
        echo "✅ 성공: {$result['order_no']}\n";
    } else {
        echo "❌ 실패: {$result['order_no']} - {$result['message']}\n";
    }
}
?>
```

## API 문서화 구조

### OpenAPI 3.0 명세
**파일**: `api-docs/swagger/kicc_ars_api_v3_batch.yaml`

주요 섹션:
- **info**: API 버전 및 설명
- **servers**: 개발/운영 서버 URL
- **paths**: 엔드포인트 정의 및 파라미터
- **responses**: 응답 예시 (성공, 부분 성공, 에러)
- **x-error-codes**: 전체 에러 코드 매핑 테이블
- **x-business-logic**: 비즈니스 로직 상세 설명

### Swagger UI 커스터마이징
**파일**: `api-docs/swagger/index.html`

- 한글 UI
- DASAM 브랜딩
- 배치 요청 예시 강조
- 에러 코드 참조 테이블

## 배포 컨텍스트

### 개발 환경
- **URL**: `https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch_json.asp`
- **용도**: 개발 및 테스트

### 운영 환경
- **URL**: `https://www.arspg.co.kr/ars/kicc/db/kicc_ars_order_v3_batch_json.asp`
- **주의사항**:
  1. `dev/db/` 디렉토리에서 먼저 테스트
  2. 모든 에러 코드 정상 작동 확인
  3. 한글 인코딩 유지 확인
  4. API 변경 시 Swagger 문서 동시 업데이트
  5. 저장 프로시저 변경 시 DBA와 사전 협의

## API 응답 형식 (JSON)

### 응답 구조
모든 API 응답은 JSON 형식으로 제공되며, 다음 두 가지 필수 필드를 포함합니다:

1. **batch_summary**: 배치 처리 요약 정보
   - `total` (integer): 총 주문 건수
   - `success` (integer): 성공 건수
   - `fail` (integer): 실패 건수

2. **req_result**: 각 주문건의 처리 결과 배열
   - `order_no` (string): 주문번호
   - `phone_no` (string): 전화번호
   - `result_code` (string): 결과 코드 (4자리)
   - `message` (string): 결과 메시지

### JSON 응답 예시

#### 전체 성공
```json
{
  "batch_summary": {
    "total": 3,
    "success": 3,
    "fail": 0
  },
  "req_result": [
    {
      "order_no": "ORD20250118001",
      "phone_no": "01024020684",
      "result_code": "0000",
      "message": "등록성공"
    },
    {
      "order_no": "ORD20250118002",
      "phone_no": "01024020684",
      "result_code": "0000",
      "message": "등록성공"
    },
    {
      "order_no": "ORD20250118003",
      "phone_no": "01024020684",
      "result_code": "0000",
      "message": "등록성공"
    }
  ]
}
```

#### 부분 성공
```json
{
  "batch_summary": {
    "total": 3,
    "success": 2,
    "fail": 1
  },
  "req_result": [
    {
      "order_no": "ORD20250118001",
      "phone_no": "01024020684",
      "result_code": "0000",
      "message": "등록성공"
    },
    {
      "order_no": "ORD20250118002",
      "phone_no": "01024020684",
      "result_code": "0000",
      "message": "등록성공"
    },
    {
      "order_no": "ORD20250118003",
      "phone_no": "01024020684",
      "result_code": "0011",
      "message": "거래번호중복"
    }
  ]
}
```

#### 에러 응답
```json
{
  "batch_summary": {
    "total": 0,
    "success": 0,
    "fail": 0
  },
  "req_result": [
    {
      "order_no": "",
      "phone_no": "01024020684",
      "result_code": "0002",
      "message": "주문번호누락 (orders 배열 필요)"
    }
  ]
}
```

### 응답 특징
- **Content-Type**: `application/json; charset=utf-8`
- **일관성**: 성공/실패 모든 경우에 동일한 구조
- **필수 필드**: `batch_summary`는 예외 없이 항상 포함
- **UTF-8 인코딩**: 한글 데이터 완전 지원

## 개발 시 체크리스트

1. ✅ UTF-8 인코딩 유지 (한글 깨짐 방지)
2. ✅ JSON orders 배열 처리 검증
3. ✅ orders 배열 필수 필드 확인 (order_no, amount, cc_pord_desc)
4. ✅ 부분 성공 시나리오 테스트
5. ✅ Swagger 문서 동기화
6. ✅ 에러 코드 정확성 검증
7. ✅ SQL 인젝션 방지 검토
8. ✅ CORS 정책 검토 (운영 환경)

