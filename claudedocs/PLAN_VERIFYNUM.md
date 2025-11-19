# 인증번호 생성 통합 설계 문서

## 개요

**목적**: ARS, SMS, KTK 모든 타입에 대해 인증번호를 생성하며, 배치 주문 시 단일 인증번호를 복수 주문건에 동일하게 적용

**대상 파일**: `dev/db/kicc_ars_order_v3_batch.asp`

**작성일**: 2025-01-19

---

## 1. 현재 구현 분석

### 1.1 현재 동작 방식

**파일**: `dev/db/kicc_ars_order_v3_batch.asp` (라인 487-608)

```vbscript
'// 현재: SMS/KTK 타입만 인증번호 생성
If req_type = "SMS" Or req_type = "KTK" Then
  '// 각 주문건마다 인증번호 생성 (비효율적)
  For i = 0 To orderCount - 1
    '// sp_getKiccAuthNo 호출
    '// SMS 발송 (em_smt_tran/em_mmt_tran 테이블)
  Next
End If
```

**현재 문제점**:
1. **ARS 타입 미지원**: ARS 타입 주문에는 인증번호가 생성되지 않음
2. **중복 생성**: 배치 내 각 주문건마다 별도 인증번호 생성 (성능 낭비)
3. **SMS 발송 혼재**: 인증번호 생성 로직과 SMS 발송 로직이 분리되지 않음
4. **코드 위치**: 주문 처리 루프 내부에 위치 (라인 491-608)

### 1.2 현재 인증번호 생성 프로세스

**저장 프로시저**: `sp_getKiccAuthNo`
- **기능**: 순차적으로 증가하는 6자리 숫자 생성
- **형식**: `000100`, `000101`, `000102`, ...
- **호출 빈도**: 배치 내 각 주문건마다 호출 (비효율)

**SMS 발송**:
- **테이블**: `em_smt_tran` (SMS), `em_mmt_tran` (MMS)
- **데이터베이스**: `imds` (211.196.157.121)
- **발송 조건**: SMS/KTK 타입일 때만 발송
- **메시지 형식**: `{고객명} 님의 주문인증번호는[{인증번호}]입니다 {콜백번호} 로전화주십시오`

---

## 2. 요구사항 정의

### 2.1 기능 요구사항

#### FR-1: 모든 타입에 인증번호 생성
- **현재**: SMS/KTK 타입만 인증번호 생성
- **변경 후**: **ARS, SMS, KTK 모든 타입**에 인증번호 생성

#### FR-2: 배치당 단일 인증번호 생성
- **현재**: 배치 내 각 주문건마다 별도 인증번호 생성
- **변경 후**: **배치당 1개의 인증번호 생성**, 모든 주문건에 동일 적용

#### FR-3: SMS 발송 분리
- **ARS 타입**: 인증번호 생성만 수행, **SMS 발송 안 함**
- **SMS/KTK 타입**: 인증번호 생성 + **SMS/MMS 발송 수행**

#### FR-4: 데이터베이스 저장
- **모든 타입**: `KICC_SHOP_ORDER.auth_no` 필드에 인증번호 저장
- **배치 내 모든 주문**: 동일한 인증번호 값 저장

### 2.2 비기능 요구사항

#### NFR-1: 성능 최적화
- **sp_getKiccAuthNo 호출**: 배치당 1회만 호출 (현재: 주문건당 1회)
- **SMS DB 연결**: SMS/KTK 타입일 때만 연결 (불필요한 연결 제거)

#### NFR-2: 코드 구조 개선
- **인증번호 생성 로직**: 주문 처리 루프 **외부**로 이동
- **SMS 발송 로직**: 조건부 실행 (request_type 기반)
- **관심사 분리**: 인증번호 생성 vs SMS 발송

#### NFR-3: 하위 호환성
- **기존 API 호환**: 요청/응답 형식 변경 없음
- **데이터베이스 스키마**: 기존 테이블 구조 유지
- **에러 코드**: 기존 코드 체계 유지

---

## 3. 설계 상세

### 3.1 처리 흐름도

```
[요청 수신]
    ↓
[파라미터 검증]
    ↓
[가맹점 정보 조회] (sp_getKiccShopInfo)
    ↓
[★ 인증번호 생성] ← 배치당 1회 (모든 타입)
    ↓              sp_getKiccAuthNo 호출
    ↓              maxcode = "000100" (6자리)
    ↓
[주문 처리 루프]
    ↓
    [주문 1] → [중복 확인] → [주문 저장 (auth_no = maxcode)]
    [주문 2] → [중복 확인] → [주문 저장 (auth_no = maxcode)]
    [주문 N] → [중복 확인] → [주문 저장 (auth_no = maxcode)]
    ↓
[★ SMS 발송] ← SMS/KTK 타입만 (배치당 1회)
    ↓           em_smt_tran/em_mmt_tran 등록
    ↓
[응답 반환]
```

### 3.2 코드 구조 재설계

#### 3.2.1 현재 코드 구조 (AS-IS)

```vbscript
'// 라인 417-433: 데이터베이스 연결 및 초기화
'// 라인 434-666: 주문 처리 루프
For i = 0 To orderCount - 1
  '// 라인 449-478: 개별 주문 검증
  '// 라인 480-486: 중복 확인
  '// 라인 487-608: ★ 인증번호 생성 + SMS 발송 (각 주문건마다)
  '// 라인 610-643: 주문 저장
Next
```

**문제점**:
- 인증번호 생성이 루프 **내부**에 위치
- 각 주문건마다 `sp_getKiccAuthNo` 호출
- SMS 발송 로직과 혼재

#### 3.2.2 개선된 코드 구조 (TO-BE)

```vbscript
'// ========================================
'// 배치 인증번호 생성 (모든 타입)
'// ========================================
'// 위치: 주문 처리 루프 이전 (라인 424~440 사이 삽입)

Dim maxcode, callback_no, tempCode, j, arsRs
maxcode = ""

'// 모든 타입에 대해 인증번호 생성
set cmd = Server.CreateObject("ADODB.Command")
with cmd
    .ActiveConnection = strConnect
    .CommandType = adCmdStoredProc
    .CommandTimeout = 60
    .CommandText = "sp_getKiccAuthNo"
    set arsRs = .Execute
end with
set cmd = nothing

If IsNull(arsRs(0)) then
  maxcode = "000100"
Else
  tempCode = ""
  for j=1 to 6-len(arsRs(0))
    tempCode = tempCode & "0"
  next
  maxcode = tempCode & arsRs(0)
End if
arsRs.close
Set arsRs = nothing

'// ========================================
'// 주문 처리 루프
'// ========================================
For i = 0 To orderCount - 1
  '// 개별 주문 검증
  '// 중복 확인
  '// 주문 저장 (auth_no = maxcode 사용)
Next

'// ========================================
'// SMS/MMS 발송 (조건부)
'// ========================================
'// 위치: 주문 처리 루프 이후 (라인 667 이후 삽입)

If req_type = "SMS" Or req_type = "KTK" Then
  '// 콜백번호 설정
  If ars_dnis <> "" Then
    callback_no = "02-3490-" & ars_dnis
  Else
    callback_no = "02-3490-4411"
  End if

  '// SMS/MMS 메시지 생성
  Dim smsMsg, msgLength, useMMS, smsRs

  If sms_message <> "" Then
    smsMsg = sms_message & " " & cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
  Else
    smsMsg = cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
  End If
  smsMsg = smsMsg & callback_no & " 로전화주십시오"

  '// 메시지 길이 체크
  msgLength = Len(smsMsg)
  useMMS = 0
  If msgLength >= 80 Then
    useMMS = 1
  End If

  '// SMS/MMS 발송 (배치당 1회만)
  Set smsRs = Server.CreateObject("ADODB.Recordset")

  '// MMS/SMS 테이블 등록 로직
  '// ... (기존 코드 재사용)

  smsRs.Close
  Set smsRs = nothing
End If
```

### 3.3 핵심 변경 사항

#### 변경 1: 인증번호 생성 시점 이동
**위치**: 라인 424~440 사이 (가맹점 정보 조회 직후, 주문 루프 진입 전)

```vbscript
'// ========================================
'// 배치 인증번호 생성 (모든 타입 공통)
'// ========================================
'// 라인 424 이후 삽입

Dim maxcode, tempCode, j, arsRs, cmd
maxcode = ""

'// 인증번호 생성 (배치당 1회)
set cmd = Server.CreateObject("ADODB.Command")
with cmd
    .ActiveConnection = strConnect
    .CommandType = adCmdStoredProc
    .CommandTimeout = 60
    .CommandText = "sp_getKiccAuthNo"
    set arsRs = .Execute
end with
set cmd = nothing

If IsNull(arsRs(0)) then
  maxcode = "000100"
Else
  tempCode = ""
  for j=1 to 6-len(arsRs(0))
    tempCode = tempCode & "0"
  next
  maxcode = tempCode & arsRs(0)
End if
arsRs.close
Set arsRs = nothing
```

**효과**:
- `sp_getKiccAuthNo` 호출 횟수: N회 → **1회** (N = 주문건수)
- 모든 타입(ARS/SMS/KTK)에 동일하게 적용

#### 변경 2: 주문 루프 단순화
**위치**: 라인 487-608 제거, 라인 637 수정

```vbscript
'// 기존 라인 487-608 제거 (인증번호 생성 + SMS 발송 로직)

'// 라인 637 수정: maxcode 변수 직접 사용
If maxcode <> "" Then
  .Fields("auth_no") = maxcode
End if
```

**효과**:
- 주문 루프 내부에서 인증번호 관련 조건문 제거
- 모든 주문건에 동일한 `maxcode` 값 저장
- 코드 가독성 향상

#### 변경 3: SMS 발송 로직 분리
**위치**: 라인 667 이후 (주문 루프 종료 직후, 응답 반환 전)

```vbscript
'// ========================================
'// SMS/MMS 발송 (조건부 실행)
'// ========================================
'// 라인 667 이후 삽입

If req_type = "SMS" Or req_type = "KTK" Then
  '// 콜백번호 설정
  Dim callback_no
  If ars_dnis <> "" Then
    callback_no = "02-3490-" & ars_dnis
  Else
    callback_no = "02-3490-4411"
  End if

  '// SMS/MMS 메시지 생성
  Dim smsMsg, msgLength, useMMS, smsRs

  If sms_message <> "" Then
    smsMsg = sms_message & " " & cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
  Else
    smsMsg = cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
  End If
  smsMsg = smsMsg & callback_no & " 로전화주십시오"

  '// 메시지 길이 체크: 80자 이상이면 MMS
  msgLength = Len(smsMsg)
  useMMS = 0
  If msgLength >= 80 Then
    useMMS = 1
  End If

  '// SMS/MMS 발송 (배치당 1회만)
  Set smsRs = Server.CreateObject("ADODB.Recordset")

  If useMMS = 1 Then
    '// MMS 전송 (em_mmt_tran)
    On Error Resume Next
    with smsRs
      .Open "em_mmt_tran", strConnectSMS, adOpenDynamic, adLockOptimistic
      .AddNew
      .Fields("mt_refkey")       = terminal_id & "@BATCH"  '// 배치 식별
      .Fields("priority")        = "S"
      .Fields("msg_class")       = "1"
      .Fields("date_client_req") = now()
      If mms_subject <> "" Then
        .Fields("subject")       = mms_subject
      Else
        .Fields("subject")       = "KICC 결제 안내"
      End If
      .Fields("content_type")    = "0"
      .Fields("content")         = smsMsg
      .Fields("callback")        = callback_no
      .Fields("service_type")    = "0"
      .Fields("broadcast_yn")    = "N"
      .Fields("msg_status")      = "1"
      .Fields("recipient_num")   = phone_no
      .Fields("country_code")    = "82"
      .Fields("charset")         = "UTF-8"
      .Fields("crypto_yn")       = "Y"
      .Fields("rs_id")           = "KICC"
      .Update
    End with
    If Err.Number <> 0 Then
      '// MMS 실패 시 SMS로 폴백
      smsRs.Close
      Set smsRs = Server.CreateObject("ADODB.Recordset")
      with smsRs
        .Open "em_smt_tran", strConnectSMS, adOpenDynamic, adLockOptimistic
        .AddNew
        .Fields("mt_refkey")       = terminal_id & "@BATCH"
        .Fields("rs_id")           = "KICC"
        .Fields("date_client_req") = now()
        .Fields("content")         = smsMsg
        .Fields("callback")        = callback_no
        .Fields("service_type")    = "0"
        .Fields("broadcast_yn")    = "N"
        .Fields("msg_status")      = "1"
        .Fields("recipient_num")   = phone_no
        .Update
      End with
    End If
    Err.Clear
  Else
    '// SMS 전송 (em_smt_tran)
    with smsRs
      .Open "em_smt_tran", strConnectSMS, adOpenDynamic, adLockOptimistic
      .AddNew
      .Fields("mt_refkey")       = terminal_id & "@BATCH"
      .Fields("rs_id")           = "KICC"
      .Fields("date_client_req") = now()
      .Fields("content")         = smsMsg
      .Fields("callback")        = callback_no
      .Fields("service_type")    = "0"
      .Fields("broadcast_yn")    = "N"
      .Fields("msg_status")      = "1"
      .Fields("recipient_num")   = phone_no
      .Update
    End with
  End If

  smsRs.Close
  Set smsRs = nothing
End If
```

**효과**:
- SMS 발송: 배치당 1회만 수행 (현재: 주문건당 N회)
- ARS 타입: SMS 발송 로직 실행 안 함 (성능 최적화)
- `mt_refkey` 변경: `terminal_id@order_no` → `terminal_id@BATCH` (배치 단위 식별)

---

## 4. 데이터베이스 영향 분석

### 4.1 테이블 변경사항

#### KICC_SHOP_ORDER 테이블
**변경**: 없음 (기존 스키마 유지)

**필드**: `auth_no` (VARCHAR)
- **현재**: SMS/KTK 타입만 값 저장, ARS 타입은 NULL
- **변경 후**: **모든 타입에 동일한 인증번호 저장**

**예시 데이터**:

| order_no | terminal_id | request_type | auth_no | 비고 |
|----------|-------------|--------------|---------|------|
| ORD001 | TERM001 | ARS | 000123 | 배치 공통 |
| ORD002 | TERM001 | ARS | 000123 | 배치 공통 |
| ORD003 | TERM001 | ARS | 000123 | 배치 공통 |

#### em_smt_tran / em_mmt_tran 테이블
**변경**: `mt_refkey` 필드 값 변경

**현재**:
```
mt_refkey = terminal_id & "@" & currentOrderNo
예: "TERM001@ORD001", "TERM001@ORD002", "TERM001@ORD003"
```

**변경 후**:
```
mt_refkey = terminal_id & "@BATCH"
예: "TERM001@BATCH" (배치당 1건만 등록)
```

**효과**:
- SMS 발송 건수 감소: N건 → 1건
- SMS 서버 부하 감소
- 중복 메시지 발송 방지

### 4.2 저장 프로시저 사용

#### sp_getKiccAuthNo
**현재 호출 횟수**: 배치 내 주문건수 × 1회
- 예: 3건 배치 → 3회 호출 → 인증번호 3개 생성

**변경 후 호출 횟수**: 배치당 1회
- 예: 3건 배치 → 1회 호출 → 인증번호 1개 생성

**데이터베이스 부하**:
- 저장 프로시저 실행 횟수 감소
- 시퀀스 생성 트랜잭션 감소

---

## 5. 성능 영향 분석

### 5.1 배치 크기별 성능 비교

#### 시나리오 1: 소규모 배치 (3건)

**현재 (AS-IS)**:
```
sp_getKiccAuthNo 호출: 3회
SMS 발송: 3회 (SMS/KTK 타입)
총 DB 작업: 6회
```

**변경 후 (TO-BE)**:
```
sp_getKiccAuthNo 호출: 1회
SMS 발송: 1회 (SMS/KTK 타입)
총 DB 작업: 2회
성능 개선: 67% 감소
```

#### 시나리오 2: 중규모 배치 (10건)

**현재 (AS-IS)**:
```
sp_getKiccAuthNo 호출: 10회
SMS 발송: 10회 (SMS/KTK 타입)
총 DB 작업: 20회
```

**변경 후 (TO-BE)**:
```
sp_getKiccAuthNo 호출: 1회
SMS 발송: 1회 (SMS/KTK 타입)
총 DB 작업: 2회
성능 개선: 90% 감소
```

#### 시나리오 3: 대규모 배치 (50건)

**현재 (AS-IS)**:
```
sp_getKiccAuthNo 호출: 50회
SMS 발송: 50회 (SMS/KTK 타입)
총 DB 작업: 100회
```

**변경 후 (TO-BE)**:
```
sp_getKiccAuthNo 호출: 1회
SMS 발송: 1회 (SMS/KTK 타입)
총 DB 작업: 2회
성능 개선: 98% 감소
```

### 5.2 성능 개선 효과

| 배치 크기 | 현재 DB 작업 | 변경 후 DB 작업 | 감소율 |
|-----------|--------------|-----------------|--------|
| 3건 | 6회 | 2회 | 67% |
| 10건 | 20회 | 2회 | 90% |
| 50건 | 100회 | 2회 | 98% |

**핵심 개선 사항**:
- 배치 크기가 클수록 성능 개선 효과 증대
- DB 서버 부하 감소 (sp_getKiccAuthNo 호출 횟수)
- SMS 서버 부하 감소 (중복 발송 방지)

---

## 6. 테스트 계획

### 6.1 단위 테스트

#### TC-1: ARS 타입 인증번호 생성
**입력**:
```json
{
  "mode": "ars_data_add",
  "terminal_id": "05532206",
  "request_type": "ARS",
  "orders": [
    {"order_no": "ARS001", "amount": 1000, "cc_pord_desc": "상품A"},
    {"order_no": "ARS002", "amount": 2000, "cc_pord_desc": "상품B"}
  ]
}
```

**예상 결과**:
- `sp_getKiccAuthNo` 호출: 1회
- 인증번호 생성: 1개 (예: "000123")
- `KICC_SHOP_ORDER.auth_no`: 모든 주문에 "000123" 저장
- SMS 발송: 없음
- 응답: `result_code: "0000"` (2건 모두 성공)

#### TC-2: SMS 타입 인증번호 생성 + 발송
**입력**:
```json
{
  "mode": "ars_data_add",
  "terminal_id": "05532206",
  "request_type": "SMS",
  "cc_name": "홍길동",
  "phone_no": "01012345678",
  "orders": [
    {"order_no": "SMS001", "amount": 1000, "cc_pord_desc": "상품A"},
    {"order_no": "SMS002", "amount": 2000, "cc_pord_desc": "상품B"}
  ]
}
```

**예상 결과**:
- `sp_getKiccAuthNo` 호출: 1회
- 인증번호 생성: 1개 (예: "000124")
- `KICC_SHOP_ORDER.auth_no`: 모든 주문에 "000124" 저장
- SMS 발송: 1회 (`em_smt_tran` 테이블 등록 1건)
- SMS 메시지: "홍길동 님의 주문인증번호는[000124]입니다 02-3490-XXXX 로전화주십시오"
- 응답: `result_code: "0000"` (2건 모두 성공)

#### TC-3: KTK 타입 MMS 발송
**입력**:
```json
{
  "mode": "ars_data_add",
  "terminal_id": "05532206",
  "request_type": "KTK",
  "cc_name": "김철수",
  "phone_no": "01087654321",
  "sms_message": "안녕하세요 고객님, 결제를 도와드리겠습니다.",
  "mms_subject": "결제 안내",
  "orders": [
    {"order_no": "KTK001", "amount": 5000, "cc_pord_desc": "프리미엄 상품"}
  ]
}
```

**예상 결과**:
- `sp_getKiccAuthNo` 호출: 1회
- 인증번호 생성: 1개 (예: "000125")
- `KICC_SHOP_ORDER.auth_no`: "000125" 저장
- MMS 발송: 1회 (`em_mmt_tran` 테이블 등록 1건, 메시지 길이 >= 80자)
- MMS 메시지: "안녕하세요 고객님, 결제를 도와드리겠습니다. 김철수 님의 주문인증번호는[000125]입니다 02-3490-XXXX 로전화주십시오"
- 응답: `result_code: "0000"`

### 6.2 통합 테스트

#### TC-4: 혼합 타입 배치 (연속 요청)
**시나리오**: ARS → SMS → KTK 순서로 연속 요청

**ARS 요청**:
```json
{"request_type": "ARS", "orders": [{"order_no": "MIX001", ...}]}
```
**예상 인증번호**: "000126"

**SMS 요청**:
```json
{"request_type": "SMS", "orders": [{"order_no": "MIX002", ...}]}
```
**예상 인증번호**: "000127"
**SMS 발송**: 1회

**KTK 요청**:
```json
{"request_type": "KTK", "orders": [{"order_no": "MIX003", ...}]}
```
**예상 인증번호**: "000128"
**SMS 발송**: 1회

**검증**:
- 각 배치마다 고유한 인증번호 생성
- SMS 발송은 SMS/KTK 타입만 수행
- 인증번호 순차 증가 확인

#### TC-5: 대용량 배치 (50건)
**입력**:
```json
{
  "request_type": "SMS",
  "orders": [
    {"order_no": "BULK001", ...},
    {"order_no": "BULK002", ...},
    ...
    {"order_no": "BULK050", ...}
  ]
}
```

**예상 결과**:
- `sp_getKiccAuthNo` 호출: 1회만
- 모든 주문에 동일한 인증번호 저장
- SMS 발송: 1회만
- 처리 시간: 현재 대비 90% 이상 단축

### 6.3 에러 시나리오

#### TC-6: 인증번호 생성 실패
**조건**: `sp_getKiccAuthNo` 저장 프로시저 실패

**예상 결과**:
- `maxcode = "000100"` (기본값 사용)
- 주문 처리 정상 진행
- 에러 로그 기록 필요 (향후 개선)

#### TC-7: SMS 발송 실패
**조건**: `em_smt_tran` 테이블 INSERT 실패

**예상 결과**:
- 주문 저장은 정상 완료 (트랜잭션 분리)
- SMS 발송 실패는 주문 성공에 영향 없음
- 배치 응답: `result_code: "0000"` (주문 성공)

---

## 7. 구현 가이드

### 7.1 구현 단계

#### Phase 1: 인증번호 생성 로직 이동 (우선순위: 높음)
**작업 내용**:
1. 라인 491-519 코드 → 라인 424 이후로 이동
2. 조건문 제거: `If req_type = "SMS" Or req_type = "KTK" Then`
3. 변수 선언 위치 조정

**테스트**:
- TC-1 (ARS 타입 인증번호 생성)
- TC-2 (SMS 타입 인증번호 생성)

#### Phase 2: 주문 루프 단순화 (우선순위: 높음)
**작업 내용**:
1. 라인 487-608 제거 (인증번호 생성 + SMS 발송 로직)
2. 라인 637 수정: `maxcode` 변수 직접 사용
3. 루프 내부 조건문 제거

**테스트**:
- TC-1, TC-2 재검증
- TC-5 (대용량 배치)

#### Phase 3: SMS 발송 로직 분리 (우선순위: 중간)
**작업 내용**:
1. 라인 667 이후에 SMS 발송 로직 추가
2. 조건: `If req_type = "SMS" Or req_type = "KTK" Then`
3. `mt_refkey` 변경: `terminal_id@BATCH`

**테스트**:
- TC-2, TC-3 재검증
- TC-7 (SMS 발송 실패)

#### Phase 4: 통합 테스트 (우선순위: 높음)
**작업 내용**:
1. 모든 타입 테스트 (ARS, SMS, KTK)
2. 성능 측정 (배치 크기별)
3. 에러 시나리오 검증

**테스트**:
- TC-4 (혼합 타입 배치)
- TC-5 (대용량 배치)
- TC-6, TC-7 (에러 시나리오)

### 7.2 주의사항

#### 코딩 표준
- **UTF-8 인코딩 유지**: 한글 깨짐 방지
- **변수 선언 위치**: ASP는 함수/루프 시작 전 선언 필요
- **에러 처리**: `On Error Resume Next` 사용 시 `Err.Clear` 필수

#### 데이터베이스
- **트랜잭션 분리**: 주문 저장 vs SMS 발송은 독립적으로 처리
- **연결 문자열**: `strConnect` (주문), `strConnectSMS` (SMS) 구분
- **저장 프로시저**: `sp_getKiccAuthNo` 호출 전 연결 확인

#### SMS 발송
- **메시지 길이**: 80자 기준 SMS/MMS 자동 선택
- **mt_refkey 변경**: 기존 시스템 영향도 확인 필요
- **폴백 로직**: MMS 실패 시 SMS로 자동 전환

---

## 8. 롤백 계획

### 8.1 롤백 조건

다음 중 하나라도 발생 시 즉시 롤백:

1. **기능 오류**:
   - ARS 타입 주문에 인증번호가 저장되지 않음
   - SMS/KTK 타입에서 SMS 발송 실패율 증가
   - 배치 처리 실패율 증가 (현재 대비 5% 이상)

2. **성능 저하**:
   - 응답 시간 증가 (현재 대비 20% 이상)
   - 데이터베이스 부하 증가 (CPU/메모리)
   - SMS 서버 오류 발생

3. **데이터 이슈**:
   - 인증번호 중복 발생
   - 주문 데이터 누락
   - SMS 발송 데이터 불일치

### 8.2 롤백 절차

#### Step 1: 백업 파일 복원
```bash
# 개발 서버
copy dev\db\kicc_ars_order_v3_batch.asp.backup dev\db\kicc_ars_order_v3_batch.asp

# 운영 서버 (필요 시)
copy db\kicc_ars_order_v3_batch.asp.backup db\kicc_ars_order_v3_batch.asp
```

#### Step 2: 데이터 정합성 확인
```sql
-- 인증번호 중복 확인
SELECT auth_no, COUNT(*) as cnt
FROM KICC_SHOP_ORDER
WHERE auth_no IS NOT NULL
GROUP BY auth_no
HAVING COUNT(*) > 1;

-- SMS 발송 데이터 확인
SELECT mt_refkey, COUNT(*) as cnt
FROM imds.dbo.em_smt_tran
WHERE mt_refkey LIKE '%@BATCH'
GROUP BY mt_refkey;
```

#### Step 3: 모니터링 재개
- 롤백 후 30분간 집중 모니터링
- 에러 로그 확인
- 성능 지표 확인

---

## 9. 운영 고려사항

### 9.1 모니터링 포인트

#### 기능 모니터링
- **인증번호 생성 성공률**: 99% 이상 유지
- **SMS 발송 성공률**: 95% 이상 유지 (현재 수준)
- **배치 처리 성공률**: 현재 수준 유지

#### 성능 모니터링
- **평균 응답 시간**: 현재 대비 감소 확인
- **sp_getKiccAuthNo 호출 횟수**: 배치당 1회 확인
- **SMS 발송 건수**: 배치당 1회 확인

#### 데이터 모니터링
- **auth_no NULL 비율**: ARS 타입 0%, SMS/KTK 타입 0%
- **인증번호 중복**: 발생 시 즉시 알림
- **SMS mt_refkey 형식**: `terminal_id@BATCH` 형식 확인

### 9.2 장애 대응

#### 시나리오 1: 인증번호 생성 실패
**증상**: `sp_getKiccAuthNo` 저장 프로시저 오류

**대응**:
1. 기본값 사용 확인: `maxcode = "000100"`
2. 데이터베이스 연결 상태 확인
3. 저장 프로시저 로그 확인
4. DBA 에스컬레이션

#### 시나리오 2: SMS 발송 대량 실패
**증상**: `em_smt_tran/em_mmt_tran` INSERT 오류

**대응**:
1. 주문 저장은 정상 완료 확인
2. SMS 서버 연결 상태 확인 (211.196.157.121)
3. SMS 데이터베이스 용량 확인
4. SMS 담당자 에스컬레이션

#### 시나리오 3: 성능 저하
**증상**: 응답 시간 증가, 타임아웃 발생

**대응**:
1. 배치 크기 확인 (50건 이상 여부)
2. 데이터베이스 서버 부하 확인
3. 네트워크 지연 확인
4. 필요 시 롤백 고려

---

## 10. 문서 이력

| 버전 | 작성일 | 작성자 | 변경 내역 |
|------|--------|--------|-----------|
| 1.0 | 2025-01-19 | Claude Code | 초안 작성 |

---

## 11. 참고 자료

### 관련 문서
- `CLAUDE.md`: 프로젝트 전체 개요 및 기술 스택
- `dev/db/kicc_ars_order_v3_batch.asp`: 현재 구현 소스코드

### 데이터베이스 스키마
- **테이블**: `KICC_SHOP_ORDER` (주문), `em_smt_tran` (SMS), `em_mmt_tran` (MMS)
- **저장 프로시저**: `sp_getKiccShopInfo`, `sp_getKiccAuthNo`

### 테스트 환경
- **개발 서버**: `https://www.arspg.co.kr/ars/kicc/dev/db/`
- **운영 서버**: `https://www.arspg.co.kr/ars/kicc/db/`

---

## 부록: 코드 비교

### A. 인증번호 생성 로직 비교

#### AS-IS (현재)
```vbscript
'// 라인 491-519 (주문 루프 내부)
If req_type = "SMS" Or req_type = "KTK" Then
  '// 각 주문건마다 실행
  set cmd = Server.CreateObject("ADODB.Command")
  with cmd
      .ActiveConnection = strConnect
      .CommandType = adCmdStoredProc
      .CommandTimeout = 60
      .CommandText = "sp_getKiccAuthNo"
      set arsRs = .Execute
  end with
  set cmd = nothing

  If IsNull(arsRs(0)) then
    maxcode = "000100"
  Else
    tempCode = ""
    for j=1 to 6-len(arsRs(0))
      tempCode = tempCode & "0"
    next
    maxcode = tempCode & arsRs(0)
  End if
  arsRs.close
  Set arsRs = nothing
End If
```

#### TO-BE (변경 후)
```vbscript
'// 라인 424 이후 (주문 루프 진입 전)
'// 모든 타입에 대해 1회만 실행
Dim maxcode, tempCode, j, arsRs, cmd
maxcode = ""

set cmd = Server.CreateObject("ADODB.Command")
with cmd
    .ActiveConnection = strConnect
    .CommandType = adCmdStoredProc
    .CommandTimeout = 60
    .CommandText = "sp_getKiccAuthNo"
    set arsRs = .Execute
end with
set cmd = nothing

If IsNull(arsRs(0)) then
  maxcode = "000100"
Else
  tempCode = ""
  for j=1 to 6-len(arsRs(0))
    tempCode = tempCode & "0"
  next
  maxcode = tempCode & arsRs(0)
End if
arsRs.close
Set arsRs = nothing
```

**주요 변경점**:
1. ✅ 조건문 제거: `If req_type = "SMS" Or req_type = "KTK" Then`
2. ✅ 위치 이동: 주문 루프 내부 → 주문 루프 진입 전
3. ✅ 실행 횟수: 주문건수 × 1회 → 배치당 1회

### B. SMS 발송 로직 비교

#### AS-IS (현재)
```vbscript
'// 라인 491-608 (주문 루프 내부, 각 주문건마다 실행)
If req_type = "SMS" Or req_type = "KTK" Then
  '// 콜백번호 설정
  If ars_dnis <> "" Then
    callback_no = "02-3490-" & ars_dnis
  Else
    callback_no = "02-3490-4411"
  End if

  '// SMS 메시지 생성
  smsMsg = cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 " & callback_no & " 로전화주십시오"

  '// SMS 발송 (각 주문건마다)
  Set smsRs = Server.CreateObject("ADODB.Recordset")
  with smsRs
    .Open "em_smt_tran", strConnectSMS, adOpenDynamic, adLockOptimistic
    .AddNew
    .Fields("mt_refkey") = terminal_id & "@" & currentOrderNo  '// 주문건별 식별
    .Fields("content") = smsMsg
    '// ... 기타 필드
    .Update
  End with
  smsRs.Close
  Set smsRs = nothing
End If
```

#### TO-BE (변경 후)
```vbscript
'// 라인 667 이후 (주문 루프 종료 후, 배치당 1회만 실행)
If req_type = "SMS" Or req_type = "KTK" Then
  '// 콜백번호 설정
  Dim callback_no
  If ars_dnis <> "" Then
    callback_no = "02-3490-" & ars_dnis
  Else
    callback_no = "02-3490-4411"
  End if

  '// SMS 메시지 생성
  Dim smsMsg, msgLength, useMMS, smsRs
  smsMsg = cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 " & callback_no & " 로전화주십시오"

  '// 메시지 길이 체크
  msgLength = Len(smsMsg)
  useMMS = 0
  If msgLength >= 80 Then
    useMMS = 1
  End If

  '// SMS 발송 (배치당 1회만)
  Set smsRs = Server.CreateObject("ADODB.Recordset")
  with smsRs
    .Open "em_smt_tran", strConnectSMS, adOpenDynamic, adLockOptimistic
    .AddNew
    .Fields("mt_refkey") = terminal_id & "@BATCH"  '// 배치 단위 식별
    .Fields("content") = smsMsg
    '// ... 기타 필드
    .Update
  End with
  smsRs.Close
  Set smsRs = nothing
End If
```

**주요 변경점**:
1. ✅ 위치 이동: 주문 루프 내부 → 주문 루프 종료 후
2. ✅ 실행 횟수: 주문건수 × 1회 → 배치당 1회
3. ✅ mt_refkey 변경: `terminal_id@order_no` → `terminal_id@BATCH`

---

**설계 문서 작성 완료**
