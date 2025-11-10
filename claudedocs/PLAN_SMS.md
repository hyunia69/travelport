# PLAN_SMS.md - sms_message 파라미터 추가 설계

## 개요

### 목적
KICC ARS 배치 주문 API에 `sms_message` 파라미터를 추가하여 SMS/KTK(카카오톡) 발송 시 **사용자 정의 메시지**를 전달할 수 있도록 기능을 확장합니다.

### 변경 범위
1. **ASP 백엔드**: `kicc_ars_order_v3_batch.asp`
2. **OpenAPI 명세**: `kicc_ars_api_v3_batch.yaml`
3. **Swagger UI 문서**: `index.html`

---

## 1. 요구사항 분석

### 파라미터 명세

| 속성 | 값 |
|------|-----|
| **이름** | `sms_message` |
| **타입** | `string` |
| **필수 여부** | **선택** (Optional) |
| **설명** | 문자나 카카오톡으로 전달할 사용자 정의 내용 |
| **예시** | `"고객님, 트래블포트에서 결제하실 금액은 총 100,000원 입니다"` |
| **최대 길이** | 90자 (SMS 표준 길이 제한 고려) |
| **적용 대상** | `request_type`이 `SMS` 또는 `KTK`인 경우만 사용 |
| **기본 동작** | 파라미터 미제공 시 기존 기본 메시지 형식 사용 |

### 기존 SMS 메시지 형식 (현재)

```
[고객명] 님의 주문인증번호는[XXXXXX]입니다 02-3490-XXXX 로전화주십시오
```

**예시**:
```
홍길동 님의 주문인증번호는[123456]입니다 02-3490-4411 로전화주십시오
```

### 신규 SMS 메시지 형식 (sms_message 제공 시)

```
[사용자 정의 메시지] [고객명] 님의 주문인증번호는[XXXXXX]입니다 02-3490-XXXX 로전화주십시오
```

**예시**:
```
고객님, 트래블포트에서 결제하실 금액은 총 100,000원 입니다 홍길동 님의 주문인증번호는[123456]입니다 02-3490-4411 로전화주십시오
```

### 비즈니스 로직 요구사항

1. **선택 파라미터**: `sms_message`가 없어도 기존 로직은 정상 작동
2. **타입 제한**: `request_type=ARS`인 경우 `sms_message`는 무시 (SMS 발송이 없으므로)
3. **메시지 병합**: `sms_message` + 기존 인증번호 메시지 조합
4. **길이 검증**: SMS 표준 길이 제한(90자) 초과 시 자동 잘림 또는 경고
5. **인코딩**: UTF-8 한글 메시지 정상 처리
6. **배치 공통 적용**: 배치 주문의 모든 건에 동일한 `sms_message` 적용

---

## 2. ASP 파일 수정 설계

### 파일: `dev/db/kicc_ars_order_v3_batch.asp`

#### 2.1. 파라미터 추출 섹션 (Line 196-207)

**현재 코드**:
```asp
'// 공통 파라미터 추출
strMode = ExtractJsonString(jsonBody, "mode")
terminal_id = ExtractJsonString(jsonBody, "terminal_id")
req_type = ExtractJsonString(jsonBody, "request_type")
alert_show = ExtractJsonString(jsonBody, "alert_show")
verify_num = ExtractJsonString(jsonBody, "verify_num")
cc_name = ExtractJsonString(jsonBody, "cc_name")
phone_no = ExtractJsonString(jsonBody, "phone_no")
cc_email = ExtractJsonString(jsonBody, "cc_email")
card_no = ExtractJsonString(jsonBody, "card_no")
expire_date = ExtractJsonString(jsonBody, "expire_date")
install_month = ExtractJsonString(jsonBody, "install_month")
```

**변경 코드**:
```asp
'// 공통 파라미터 추출
strMode = ExtractJsonString(jsonBody, "mode")
terminal_id = ExtractJsonString(jsonBody, "terminal_id")
req_type = ExtractJsonString(jsonBody, "request_type")
alert_show = ExtractJsonString(jsonBody, "alert_show")
verify_num = ExtractJsonString(jsonBody, "verify_num")
cc_name = ExtractJsonString(jsonBody, "cc_name")
phone_no = ExtractJsonString(jsonBody, "phone_no")
cc_email = ExtractJsonString(jsonBody, "cc_email")
card_no = ExtractJsonString(jsonBody, "card_no")
expire_date = ExtractJsonString(jsonBody, "expire_date")
install_month = ExtractJsonString(jsonBody, "install_month")
sms_message = ExtractJsonString(jsonBody, "sms_message")  '// ✨ 신규 파라미터 추가
```

**변경 위치**: Line 207 다음에 1줄 추가

---

#### 2.2. SMS 메시지 생성 로직 (Line 518-520)

**현재 코드**:
```asp
'// SMS 메시지 큐 등록
smsMsg = cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
smsMsg = smsMsg & callback_no & " 로전화주십시오"
```

**변경 코드**:
```asp
'// SMS 메시지 큐 등록
If sms_message <> "" Then
  '// 사용자 정의 메시지가 있으면 앞에 추가
  smsMsg = sms_message & " " & cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
Else
  '// 기존 기본 형식
  smsMsg = cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
End If
smsMsg = smsMsg & callback_no & " 로전화주십시오"
```

**변경 위치**: Line 518-520 전체 교체

**로직 설명**:
1. `sms_message`가 비어있지 않으면 메시지 앞에 추가
2. 기존 인증번호 메시지는 그대로 유지
3. 콜백번호는 맨 뒤에 유지

---

#### 2.3. 선택적 길이 검증 (권장사항)

**추가 위치**: Line 518 이전 (SMS 메시지 생성 전)

**선택적 검증 코드**:
```asp
'// SMS 길이 검증 (선택 사항)
If sms_message <> "" And Len(sms_message) > 90 Then
  sms_message = Left(sms_message, 90)  '// 90자로 자르기
  '// 또는 경고 로그 기록 (필요 시)
End If
```

**참고**: SMS 표준 길이는 약 90자(한글 기준 45자)이지만, 인증번호 메시지와 합쳐지므로 사용자 정의 메시지는 짧게 유지하는 것이 좋습니다.

---

#### 2.4. 변수 선언 섹션 (Line 171-174)

**현재 코드**:
```asp
Dim jsonBody, parsedOrders
Dim strMode, terminal_id, req_type, alert_show, verify_num
Dim cc_name, phone_no, cc_email
Dim card_no, expire_date, install_month
```

**변경 코드**:
```asp
Dim jsonBody, parsedOrders
Dim strMode, terminal_id, req_type, alert_show, verify_num
Dim cc_name, phone_no, cc_email
Dim card_no, expire_date, install_month, sms_message  '// ✨ 신규 변수 추가
```

**변경 위치**: Line 174 끝에 `, sms_message` 추가

---

## 3. OpenAPI 명세 수정 설계

### 파일: `api-docs/swagger/kicc_ars_api_v3_batch.yaml`

#### 3.1. 요청 스키마 - properties 섹션 (Line 161-230)

**추가 위치**: Line 222 (`cc_email` 다음)

**추가 내용**:
```yaml
                sms_message:
                  type: string
                  maxLength: 90
                  description: |
                    문자나 카카오톡으로 전달할 사용자 정의 메시지 (선택).
                    request_type이 SMS 또는 KTK인 경우에만 사용되며,
                    기본 인증번호 메시지 앞에 추가됩니다.
                  example: "고객님, 트래블포트에서 결제하실 금액은 총 100,000원 입니다"
```

**변경 후 구조**:
```yaml
properties:
  mode:
    type: string
    enum: [ars_data_add]
    description: 요청 모드 (고정값)
    example: ars_data_add

  # ... (다른 필수 파라미터들)

  cc_email:
    type: string
    format: email
    description: 고객 이메일 주소 (선택)
    example: customer@example.com

  sms_message:                           # ✨ 신규 파라미터
    type: string
    maxLength: 90
    description: |
      문자나 카카오톡으로 전달할 사용자 정의 메시지 (선택).
      request_type이 SMS 또는 KTK인 경우에만 사용되며,
      기본 인증번호 메시지 앞에 추가됩니다.
    example: "고객님, 트래블포트에서 결제하실 금액은 총 100,000원 입니다"

  alert_show:
    type: string
    enum: [Y, N]
    default: Y
    description: 응답 표시 여부
    example: Y
```

---

#### 3.2. 요청 예시 - examples 섹션 업데이트 (Line 262-307)

**변경 대상**: `sms_batch_order` 예시 (Line 288-307)

**현재 예시**:
```yaml
sms_batch_order:
  summary: SMS 배치 주문 (2건)
  description: 복수건 주문에 대해 하나의 통합 인증번호로 단일 SMS 발송
  value:
    mode: ars_data_add
    terminal_id: "05532206"
    request_type: SMS
    cc_name: 김철수
    phone_no: "01012345678"
    card_no: "1234567890123456"
    expire_date: "2512"
    install_month: "00"
    alert_show: Y
    orders:
      - order_no: "SMS20250118001"
        amount: 10000
        cc_pord_desc: "상품A"
      - order_no: "SMS20250118002"
        amount: 20000
        cc_pord_desc: "상품B"
```

**변경 예시**:
```yaml
sms_batch_order:
  summary: SMS 배치 주문 (2건) - 사용자 정의 메시지 포함
  description: 복수건 주문에 대해 하나의 통합 인증번호로 단일 SMS 발송 (사용자 정의 메시지 추가)
  value:
    mode: ars_data_add
    terminal_id: "05532206"
    request_type: SMS
    cc_name: 김철수
    phone_no: "01012345678"
    card_no: "1234567890123456"
    expire_date: "2512"
    install_month: "00"
    sms_message: "고객님, 트래블포트에서 결제하실 총 금액은 30,000원 입니다"  # ✨ 신규 필드
    alert_show: Y
    orders:
      - order_no: "SMS20250118001"
        amount: 10000
        cc_pord_desc: "상품A"
      - order_no: "SMS20250118002"
        amount: 20000
        cc_pord_desc: "상품B"
```

---

#### 3.3. 비즈니스 로직 설명 섹션 업데이트 (Line 605-610)

**추가 위치**: `x-business-logic` 섹션의 `sms_auth_number` 다음

**추가 내용**:
```yaml
  sms_custom_message:
    description: SMS/KTK 사용자 정의 메시지 기능
    parameter: sms_message
    optional: true
    max_length: 90
    format: "UTF-8 한글 지원"
    usage: "request_type이 SMS 또는 KTK인 경우에만 적용"
    message_structure: "[사용자 정의 메시지] + [기본 인증번호 메시지] + [콜백번호]"
    example_default: "홍길동 님의 주문인증번호는[123456]입니다 02-3490-4411 로전화주십시오"
    example_custom: "고객님, 결제금액 100,000원 입니다 홍길동 님의 주문인증번호는[123456]입니다 02-3490-4411 로전화주십시오"
```

---

## 4. Swagger UI 문서 수정 설계

### 파일: `api-docs/swagger/index.html`

#### 4.1. 파라미터 테이블 업데이트 (Line 235-328)

**추가 위치**: Line 319 (`cc_email` 다음)

**추가 내용**:
```html
                    <tr>
                        <td style="padding: 10px; border: 1px solid #ddd;">sms_message</td>
                        <td style="padding: 10px; border: 1px solid #ddd;">string</td>
                        <td style="padding: 10px; border: 1px solid #ddd;">
                            문자나 카카오톡으로 전달할 사용자 정의 메시지 (선택).
                            <br><small style="color: #666;">
                            request_type이 SMS 또는 KTK인 경우에만 사용되며,
                            기본 인증번호 메시지 앞에 추가됩니다. (최대 90자)
                            </small>
                        </td>
                        <td style="padding: 10px; border: 1px solid #ddd;">
                            <code>고객님, 트래블포트에서 결제하실 금액은 총 100,000원 입니다</code>
                        </td>
                    </tr>
```

**변경 후 구조**:
```html
<!-- 선택 파라미터 (Optional) -->
<tr style="background: #f5f5f5;">
    <td colspan="4" style="padding: 10px; font-weight: bold; border: 1px solid #ddd;">
        선택 파라미터 (Optional)
    </td>
</tr>

<tr>
    <td>cc_email</td>
    <td>string</td>
    <td>고객 이메일 (모든 주문에 공통 적용, 선택)</td>
    <td><code>customer@example.com</code></td>
</tr>

<!-- ✨ 신규 파라미터 추가 -->
<tr>
    <td>sms_message</td>
    <td>string</td>
    <td>문자나 카카오톡으로 전달할 사용자 정의 메시지 (선택)...</td>
    <td><code>고객님, 트래블포트에서 결제하실 금액은 총 100,000원 입니다</code></td>
</tr>

<tr>
    <td>alert_show</td>
    <td>string</td>
    <td>응답 표시 여부 (Y=표시, N=미표시)</td>
    <td><code>Y</code></td>
</tr>
```

---

#### 4.2. JavaScript/Python/PHP 예제 업데이트 (Line 511-610)

**변경 대상**: SMS 배치 주문 예제에 `sms_message` 추가

**JavaScript 예제 변경** (Line 518-545):
```javascript
// JSON orders 배열 방식 - SMS 사용자 정의 메시지 포함
fetch('https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    mode: 'ars_data_add',
    terminal_id: '05532206',
    request_type: 'SMS',
    cc_name: '홍길동',
    phone_no: '01012345678',
    card_no: '1234567890123456',
    expire_date: '2512',
    install_month: '00',
    sms_message: '고객님, 트래블포트에서 결제하실 금액은 총 100,000원 입니다',  // ✨ 신규
    orders: [
      {order_no: 'ORD001', amount: 50000, cc_pord_desc: '항공권'},
      {order_no: 'ORD002', amount: 50000, cc_pord_desc: '호텔'}
    ]
  })
})
.then(res => res.json())
.then(data => {
  console.log(`총 ${data.batch_summary.total}건 / 성공 ${data.batch_summary.success}건`);
});
```

**Python 예제 변경** (Line 550-575):
```python
# JSON orders 배열 방식 - SMS 사용자 정의 메시지 포함
import requests

url = 'https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp'
headers = {'Content-Type': 'application/json'}
payload = {
    'mode': 'ars_data_add',
    'terminal_id': '05532206',
    'request_type': 'SMS',
    'cc_name': '홍길동',
    'phone_no': '01012345678',
    'card_no': '1234567890123456',
    'expire_date': '2512',
    'install_month': '00',
    'sms_message': '고객님, 트래블포트에서 결제하실 금액은 총 100,000원 입니다',  # ✨ 신규
    'orders': [
        {'order_no': 'ORD001', 'amount': 50000, 'cc_pord_desc': '항공권'},
        {'order_no': 'ORD002', 'amount': 50000, 'cc_pord_desc': '호텔'}
    ]
}

response = requests.post(url, json=payload, headers=headers)
data = response.json()
print(f"총 {data['batch_summary']['total']}건 / 성공 {data['batch_summary']['success']}건")
```

**PHP 예제 변경** (Line 578-609):
```php
// JSON orders 배열 방식 - SMS 사용자 정의 메시지 포함
$data = [
    'mode' => 'ars_data_add',
    'terminal_id' => '05532206',
    'request_type' => 'SMS',
    'cc_name' => '홍길동',
    'phone_no' => '01012345678',
    'card_no' => '1234567890123456',
    'expire_date' => '2512',
    'install_month' => '00',
    'sms_message' => '고객님, 트래블포트에서 결제하실 금액은 총 100,000원 입니다',  // ✨ 신규
    'orders' => [
        ['order_no' => 'ORD001', 'amount' => 50000, 'cc_pord_desc' => '항공권'],
        ['order_no' => 'ORD002', 'amount' => 50000, 'cc_pord_desc' => '호텔']
    ]
];

$ch = curl_init($url);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

$response = curl_exec($ch);
curl_close($ch);
```

---

#### 4.3. 주의사항 섹션 업데이트 (Line 663-672)

**추가 위치**: Line 671 (`orders` 배열 필수 다음)

**추가 내용**:
```html
            <li><strong>사용자 정의 SMS 메시지</strong>: sms_message 파라미터는 선택 사항이며,
                제공 시 기본 인증번호 메시지 앞에 추가됨 (최대 90자 권장)</li>
```

**변경 후 구조**:
```html
<div class="alert">
    <div class="alert-title">⚠️ JSON 배치 API 중요 안내</div>
    <ul style="margin: 10px 0 0 20px;">
        <li><strong>orders 배열 필수</strong>: 각 주문 객체는 order_no, amount, cc_pord_desc 필드를 모두 포함해야 함</li>
        <li><strong>부분 성공 지원</strong>: 일부 주문 실패 시에도 성공한 주문은 정상 저장됨</li>
        <li><strong>SMS 배치 처리</strong>: 복수건 주문 시 하나의 통합 인증번호 생성 및 단일 SMS 발송</li>
        <li><strong>사용자 정의 SMS 메시지</strong>: sms_message 파라미터는 선택 사항이며,
            제공 시 기본 인증번호 메시지 앞에 추가됨 (최대 90자 권장)</li>  <!-- ✨ 신규 -->
        <li><strong>주문번호 고유성</strong>: terminal_id + order_no 조합이 고유해야 함 (중복 시 0011 에러)</li>
        <li><strong>JSON 형식 엄격</strong>: Content-Type을 application/json으로 설정하고 올바른 JSON 형식 사용</li>
    </ul>
</div>
```

---

## 5. 테스트 시나리오

### 5.1. 기본 동작 테스트

**테스트 케이스 1: sms_message 미제공 (기존 동작 유지)**
```json
{
  "mode": "ars_data_add",
  "terminal_id": "05532206",
  "request_type": "SMS",
  "cc_name": "홍길동",
  "phone_no": "01012345678",
  "card_no": "1234567890123456",
  "expire_date": "2512",
  "install_month": "00",
  "orders": [
    {"order_no": "TEST001", "amount": 10000, "cc_pord_desc": "테스트상품"}
  ]
}
```

**예상 SMS 메시지**:
```
홍길동 님의 주문인증번호는[123456]입니다 02-3490-4411 로전화주십시오
```

---

**테스트 케이스 2: sms_message 제공**
```json
{
  "mode": "ars_data_add",
  "terminal_id": "05532206",
  "request_type": "SMS",
  "cc_name": "홍길동",
  "phone_no": "01012345678",
  "card_no": "1234567890123456",
  "expire_date": "2512",
  "install_month": "00",
  "sms_message": "고객님, 트래블포트에서 결제하실 금액은 총 10,000원 입니다",
  "orders": [
    {"order_no": "TEST002", "amount": 10000, "cc_pord_desc": "테스트상품"}
  ]
}
```

**예상 SMS 메시지**:
```
고객님, 트래블포트에서 결제하실 금액은 총 10,000원 입니다 홍길동 님의 주문인증번호는[123456]입니다 02-3490-4411 로전화주십시오
```

---

**테스트 케이스 3: request_type=ARS (sms_message 무시)**
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
  "sms_message": "이 메시지는 무시됩니다",
  "orders": [
    {"order_no": "TEST003", "amount": 10000, "cc_pord_desc": "테스트상품"}
  ]
}
```

**예상 결과**: SMS 발송 없음 (ARS 타입이므로 sms_message 무시)

---

**테스트 케이스 4: 배치 주문 (모든 주문에 동일 메시지 적용)**
```json
{
  "mode": "ars_data_add",
  "terminal_id": "05532206",
  "request_type": "KTK",
  "cc_name": "김철수",
  "phone_no": "01087654321",
  "card_no": "1234567890123456",
  "expire_date": "2512",
  "install_month": "00",
  "sms_message": "트래블포트 예약금 결제 안내드립니다",
  "orders": [
    {"order_no": "TEST004", "amount": 50000, "cc_pord_desc": "항공권"},
    {"order_no": "TEST005", "amount": 30000, "cc_pord_desc": "호텔"}
  ]
}
```

**예상 SMS 메시지** (2건 주문 모두 동일):
```
트래블포트 예약금 결제 안내드립니다 김철수 님의 주문인증번호는[123456]입니다 02-3490-4411 로전화주십시오
```

---

### 5.2. 경계값 테스트

**테스트 케이스 5: 최대 길이 초과 (90자 초과)**
```json
{
  "sms_message": "이 메시지는 매우 긴 메시지입니다. SMS 표준 길이를 초과하는 메시지로 자동으로 잘려야 합니다. 테스트 목적으로 90자 이상의 긴 메시지를 작성합니다. 이 부분은 잘려야 합니다."
}
```

**예상 동작**: 첫 90자만 사용 또는 전체 메시지 사용 (구현 방식에 따라)

---

**테스트 케이스 6: 빈 문자열**
```json
{
  "sms_message": ""
}
```

**예상 동작**: 기본 메시지 형식 사용 (미제공과 동일)

---

**테스트 케이스 7: 특수문자 포함**
```json
{
  "sms_message": "결제금액: 100,000원 (세금 포함)"
}
```

**예상 SMS 메시지**:
```
결제금액: 100,000원 (세금 포함) 홍길동 님의 주문인증번호는[123456]입니다 02-3490-4411 로전화주십시오
```

---

### 5.3. UTF-8 인코딩 테스트

**테스트 케이스 8: 한글, 영문, 숫자 혼합**
```json
{
  "sms_message": "Hello! 트래블포트 결제 100,000원 입니다"
}
```

**예상 SMS 메시지**:
```
Hello! 트래블포트 결제 100,000원 입니다 홍길동 님의 주문인증번호는[123456]입니다 02-3490-4411 로전화주십시오
```

---

## 6. 구현 체크리스트

### ASP 파일 (`kicc_ars_order_v3_batch.asp`)

- [ ] **Line 174**: `sms_message` 변수 선언 추가
- [ ] **Line 207**: `sms_message = ExtractJsonString(jsonBody, "sms_message")` 파라미터 추출 추가
- [ ] **Line 518-520**: SMS 메시지 생성 로직 수정
  - `sms_message`가 비어있지 않으면 메시지 앞에 추가
  - 기본 형식은 그대로 유지
- [ ] **선택사항**: SMS 길이 검증 로직 추가 (90자 제한)

### OpenAPI 명세 (`kicc_ars_api_v3_batch.yaml`)

- [ ] **Line 222**: `sms_message` 파라미터 스키마 추가 (properties 섹션)
- [ ] **Line 288-307**: `sms_batch_order` 예시에 `sms_message` 추가
- [ ] **Line 605-610**: `sms_custom_message` 비즈니스 로직 설명 추가 (x-business-logic 섹션)

### Swagger UI 문서 (`index.html`)

- [ ] **Line 319**: 파라미터 테이블에 `sms_message` 행 추가
- [ ] **Line 518-545**: JavaScript 예제 업데이트
- [ ] **Line 550-575**: Python 예제 업데이트
- [ ] **Line 578-609**: PHP 예제 업데이트
- [ ] **Line 671**: 주의사항 섹션에 `sms_message` 안내 추가

---

## 7. 배포 계획

### 개발 환경 배포

1. **ASP 파일 업데이트**
   - 파일: `dev/db/kicc_ars_order_v3_batch.asp`
   - URL: `https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp`

2. **Swagger 문서 업데이트**
   - `api-docs/swagger/kicc_ars_api_v3_batch.yaml`
   - `api-docs/swagger/index.html`

3. **테스트 수행**
   - 테스트 케이스 1-8 모두 검증
   - UTF-8 한글 정상 인코딩 확인
   - 기존 기능 정상 작동 확인 (회귀 테스트)

### 운영 환경 배포

1. **개발 환경 검증 완료 후 진행**
2. **백업 생성**
   - 기존 ASP 파일 백업
   - 데이터베이스 현재 상태 스냅샷
3. **운영 환경 배포**
   - 파일: `db/kicc_ars_order_v3_batch.asp`
   - URL: `https://www.arspg.co.kr/ars/kicc/db/kicc_ars_order_v3_batch.asp`
4. **운영 환경 테스트**
   - Postman으로 실제 SMS 발송 테스트
   - 모니터링 및 로그 확인

---

## 8. 롤백 계획

### 문제 발생 시 롤백 절차

1. **ASP 파일 롤백**
   - 백업된 원본 ASP 파일 복원
   - IIS 재시작 (필요 시)

2. **문서 롤백**
   - `kicc_ars_api_v3_batch.yaml` 이전 버전 복원
   - `index.html` 이전 버전 복원

3. **검증**
   - 기존 API 기능 정상 작동 확인
   - 기존 SMS 발송 정상 작동 확인

---

## 9. 주의사항

### 보안 고려사항

1. **SQL 인젝션 방지**
   - `sms_message`는 데이터베이스에 직접 저장되지 않고 SMS 큐에만 전달됨
   - 현재 코드는 파라미터화된 쿼리를 사용하지 않으므로 주의 필요
   - **권장**: `sms_message`에서 특수문자 필터링 (선택사항)

2. **SMS 스팸 방지**
   - `sms_message` 길이 제한 (90자)으로 과도한 메시지 방지
   - 비정상적으로 긴 메시지 자동 잘림 처리

### 성능 고려사항

1. **데이터베이스 부하**
   - 기존 로직 변경 없음 (SMS 큐 INSERT만 수정)
   - 성능 영향 없음

2. **SMS 발송 비용**
   - 사용자 정의 메시지 추가로 SMS 길이 증가 가능
   - 장문 SMS 요금 발생 가능성 있음
   - **권장**: 사용자에게 짧은 메시지 작성 가이드 제공

### 호환성 고려사항

1. **하위 호환성**
   - `sms_message`는 선택 파라미터이므로 기존 API 호출에 영향 없음
   - 기존 클라이언트는 파라미터 미제공 시 기본 동작 유지

2. **상위 호환성**
   - 신규 파라미터 추가이므로 기존 데이터베이스 스키마 변경 없음
   - 기존 저장 프로시저 수정 없음

---

## 10. 참고 자료

### 관련 문서

- **CLAUDE.md**: 프로젝트 전체 아키텍처 및 개발 가이드
- **API 문서**: `api-docs/swagger/kicc_ars_api_v3_batch.yaml`
- **Swagger UI**: `api-docs/swagger/index.html`

### 코드 참조

- **ASP 파일**: `dev/db/kicc_ars_order_v3_batch.asp`
  - Line 60-88: `ExtractJsonString()` 함수
  - Line 90-136: `ParseJsonOrders()` 함수
  - Line 518-537: SMS 메시지 생성 및 발송 로직

### 데이터베이스

- **SMS 큐 테이블**: `imds.em_smt_tran`
  - `content` 필드: SMS 메시지 내용 저장
  - `recipient_num` 필드: 수신 전화번호

---

## 요약

이 설계 문서는 KICC ARS 배치 주문 API에 `sms_message` 파라미터를 추가하기 위한 완전한 구현 가이드입니다.

**핵심 변경사항**:
1. ASP 파일 3곳 수정 (변수 선언, 파라미터 추출, 메시지 생성)
2. OpenAPI 명세 3곳 추가 (스키마, 예시, 비즈니스 로직)
3. Swagger UI 문서 5곳 업데이트 (파라미터 테이블, 예제 3개, 주의사항)

**테스트 필수**:
- 기본 동작 (미제공 시)
- 사용자 정의 메시지 제공 시
- UTF-8 한글 인코딩
- 배치 주문 동작

**배포 순서**:
1. 개발 환경 배포 및 테스트
2. 운영 환경 배포
3. 모니터링 및 검증
