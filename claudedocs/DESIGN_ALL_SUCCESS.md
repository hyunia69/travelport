# DESIGN: 배치 주문 All-or-Nothing 트랜잭션 설계

## 1. 개요

### 1.1 현재 상태 (AS-IS)
현재 배치 주문 처리 시스템은 **부분 성공(Partial Success)** 방식으로 동작합니다:
- 3건 요청 시 1건 성공, 2건 실패 → 1건은 등록됨
- 각 주문건이 독립적으로 처리됨
- 트랜잭션 없이 순차적으로 INSERT 실행

### 1.2 목표 상태 (TO-BE)
**All-or-Nothing** 방식으로 변경:
- 3건 요청 시 1건이라도 실패하면 → 전체 등록 취소 (0건 등록)
- 모든 주문건이 성공해야만 전체 등록
- **응답 형식은 기존과 동일하게 유지** (개별 건별 결과 반환)

---

## 2. 현재 코드 분석

### 2.1 현재 처리 흐름
```
요청 수신 → 공통 파라미터 검증 → 가맹점 검증 → 인증번호 생성
    ↓
주문 루프 시작 (i = 0 to orderCount - 1)
    ├─ 개별 주문 검증 (order_no, amount, cc_pord_desc)
    ├─ 중복 체크 (SELECT)
    ├─ 성공 시 → 즉시 INSERT → successCount++
    └─ 실패 시 → failCount++ (이미 INSERT된 건은 유지)
    ↓
SMS/MMS 발송 → 결과 반환
```

### 2.2 문제점
1. **트랜잭션 부재**: 각 INSERT가 독립적으로 커밋됨
2. **롤백 불가**: 루프 중간에 실패해도 이전 INSERT는 유지됨
3. **데이터 불일치**: 배치 요청이 부분적으로만 처리됨

### 2.3 현재 코드 위치 (수정 대상)

| 라인 | 내용 | 수정 필요 |
|------|------|----------|
| 466-467 | DB 연결 생성 | 트랜잭션 시작 추가 |
| 486-587 | 주문 루프 | 2-Phase 검증으로 변경 |
| 530-564 | INSERT 실행 | Phase 2로 이동 |
| 589-591 | DB 연결 종료 | 커밋/롤백 로직 추가 |
| 599-698 | SMS 발송 | 전체 성공 조건 추가 |

---

## 3. 설계 방안

### 3.1 핵심 원칙

> **응답은 기존과 동일, DB 등록만 All-or-Nothing**

- 클라이언트가 받는 응답 형식은 변경 없음
- 각 주문건의 성공/실패 여부를 그대로 반환
- 단, 1건이라도 실패하면 DB에는 아무것도 등록하지 않음

### 3.2 2-Phase 처리 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Phase 1: 사전 검증                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 모든 주문건에 대해:                                    │   │
│  │   - 필수 필드 검증 (order_no, amount, cc_pord_desc)  │   │
│  │   - 중복 체크 (terminal_id + order_no)               │   │
│  │   - 결과 임시 저장 (기존 응답 형식 그대로)            │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │                                    │
│                         ▼                                    │
│            ┌───────────────────────┐                        │
│            │  검증 실패 건수 > 0?   │                        │
│            └───────────────────────┘                        │
│                    │           │                             │
│              Yes   │           │  No                         │
│                    ▼           ▼                             │
│  ┌─────────────────────┐  ┌─────────────────────┐          │
│  │ 응답 반환           │  │   Phase 2 진입      │          │
│  │ (INSERT 없음)       │  │                     │          │
│  │ (기존 형식 그대로)   │  │                     │          │
│  └─────────────────────┘  └─────────────────────┘          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Phase 2: 일괄 등록                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 트랜잭션 시작 (BEGIN TRANSACTION)                     │   │
│  │   ↓                                                   │   │
│  │ 모든 주문건 INSERT                                    │   │
│  │   ↓                                                   │   │
│  │ 오류 발생?                                            │   │
│  │   - Yes → ROLLBACK → 전체 실패 응답                  │   │
│  │   - No  → COMMIT → 전체 성공 응답                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │                                    │
│                         ▼                                    │
│            ┌───────────────────────┐                        │
│            │    SMS/MMS 발송       │                        │
│            │ (전체 성공 시에만)    │                        │
│            └───────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 데이터 구조 설계

#### 검증 결과 임시 저장 구조
```vbscript
'// 검증 결과 저장 배열
Dim validationResults()
ReDim validationResults(orderCount - 1, 4)
'// validationResults(i, 0) = order_no
'// validationResults(i, 1) = result_code ("0000" = 통과, 기타 = 실패)
'// validationResults(i, 2) = message
'// validationResults(i, 3) = amount
'// validationResults(i, 4) = cc_pord_desc
```

### 3.4 응답 형식 (기존과 동일하게 유지)

#### 전체 성공 시
```json
{
  "batch_summary": {
    "total": 3,
    "success": 3,
    "fail": 0
  },
  "req_result": [
    {"order_no": "ORD001", "phone_no": "01012345678", "result_code": "0000", "message": "등록성공"},
    {"order_no": "ORD002", "phone_no": "01012345678", "result_code": "0000", "message": "등록성공"},
    {"order_no": "ORD003", "phone_no": "01012345678", "result_code": "0000", "message": "등록성공"}
  ]
}
```

#### 일부 실패 시 (응답은 기존과 동일, 단 DB 등록 없음)
```json
{
  "batch_summary": {
    "total": 3,
    "success": 2,
    "fail": 1
  },
  "req_result": [
    {"order_no": "ORD001", "phone_no": "01012345678", "result_code": "0000", "message": "등록성공"},
    {"order_no": "ORD002", "phone_no": "01012345678", "result_code": "0011", "message": "거래번호중복"},
    {"order_no": "ORD003", "phone_no": "01012345678", "result_code": "0000", "message": "등록성공"}
  ]
}
```

> **주의**: 위 응답에서 `success: 2`로 표시되지만 **실제 DB에는 0건 등록됨**
>
> 클라이언트는 `fail > 0`이면 전체 등록이 취소되었음을 인지해야 함

---

## 4. 상세 구현 설계

### 4.1 Phase 1: 사전 검증 로직

```vbscript
'// ========================================
'// Phase 1: 사전 검증 (INSERT 없음)
'// ========================================

Dim validationResults()
ReDim validationResults(orderCount - 1, 4)
Dim validationFailCount
validationFailCount = 0

'// 결과 배열 초기화
ReDim resultArray(orderCount - 1)

For i = 0 To orderCount - 1
  currentOrderNo = Trim(orderNoArray(i))
  currentAmount = Trim(amountArray(i))
  currentProductDesc = Trim(productDescArray(i))

  '// 검증 결과 저장
  validationResults(i, 0) = currentOrderNo
  validationResults(i, 3) = currentAmount
  validationResults(i, 4) = currentProductDesc

  '// 필수 필드 검증
  If currentOrderNo = "" Then
    validationResults(i, 1) = "0002"
    validationResults(i, 2) = "주문번호누락"
    validationFailCount = validationFailCount + 1
    failCount = failCount + 1
  ElseIf currentAmount = "" Then
    validationResults(i, 1) = "0008"
    validationResults(i, 2) = "결제금액누락"
    validationFailCount = validationFailCount + 1
    failCount = failCount + 1
  ElseIf currentProductDesc = "" Then
    validationResults(i, 1) = "0007"
    validationResults(i, 2) = "상품명누락"
    validationFailCount = validationFailCount + 1
    failCount = failCount + 1
  Else
    '// 중복 체크
    qry = "SELECT count(order_no) cnt FROM KICC_SHOP_ORDER " & _
          "WHERE terminal_id = '" & terminal_id & "' " & _
          "AND order_no = '" & currentOrderNo & "'"
    Set rs = dbCon.Execute(qry)
    mx_cnt = rs("cnt")
    rs.close
    Set rs = nothing

    If mx_cnt > 0 Then
      validationResults(i, 1) = "0011"
      validationResults(i, 2) = "거래번호중복"
      validationFailCount = validationFailCount + 1
      failCount = failCount + 1
    Else
      validationResults(i, 1) = "0000"
      validationResults(i, 2) = "등록성공"
      successCount = successCount + 1
    End If
  End If

  '// 응답 배열 생성 (기존 형식 그대로)
  orderResult = "{" & _
    """order_no"":""" & JsonEncode(currentOrderNo) & """," & _
    """phone_no"":""" & JsonEncode(phone_no) & """," & _
    """result_code"":""" & validationResults(i, 1) & """," & _
    """message"":""" & JsonEncode(validationResults(i, 2)) & """" & _
    "}"
  resultArray(i) = orderResult
Next
```

### 4.2 검증 결과에 따른 분기 처리

```vbscript
'// ========================================
'// 검증 결과에 따른 분기
'// ========================================

If validationFailCount > 0 Then
  '// 1건이라도 실패 → DB 등록 없이 응답만 반환
  '// (응답은 기존과 동일한 형식)

  dbCon.close
  Set dbCon = nothing

  '// SMS 발송 안 함 (전체 성공이 아니므로)

  '// 응답 반환
  jsonResponse = "{" & _
    """batch_summary"":{" & _
    """total"":" & orderCount & "," & _
    """success"":" & successCount & "," & _
    """fail"":" & failCount & _
    "}," & _
    """req_result"":" & BuildJsonArray(resultArray) & _
    "}"

  response.write jsonResponse
  response.end
End If

'// 모든 검증 통과 → Phase 2 진입
```

### 4.3 Phase 2: 트랜잭션 기반 일괄 등록

```vbscript
'// ========================================
'// Phase 2: 일괄 등록 (트랜잭션 사용)
'// ========================================
'// 이 시점에서는 모든 검증이 통과된 상태

'// 트랜잭션 시작
dbCon.BeginTrans
On Error Resume Next

Dim insertError
insertError = False

For i = 0 To orderCount - 1
  currentOrderNo = validationResults(i, 0)
  currentAmount = validationResults(i, 3)
  currentProductDesc = validationResults(i, 4)

  Set adoRs = Server.CreateObject("ADODB.Recordset")
  With adoRs
    .Open "KICC_SHOP_ORDER", dbCon, adOpenDynamic, adLockOptimistic
    .AddNew
    .Fields("order_no")      = currentOrderNo
    .Fields("terminal_nm")   = terminal_nm
    .Fields("terminal_id")   = terminal_id
    .Fields("terminal_pw")   = terminal_pw
    .Fields("admin_id")      = admin_id
    .Fields("admin_name")    = admin_name
    .Fields("cust_nm")       = cc_name
    .Fields("good_nm")       = currentProductDesc
    .Fields("cust_email")    = cc_email
    .Fields("amount")        = currentAmount
    .Fields("phone_no")      = phone_no
    .Fields("payment_code")  = "0"
    .Fields("request_type")  = req_type
    If card_no <> "" Then .Fields("RESERVED_4") = card_no
    If expire_date <> "" Then .Fields("RESERVED_3") = expire_date
    If install_month <> "" Then .Fields("RESERVED_5") = install_month
    If maxcode <> "" Then .Fields("auth_no") = maxcode
    .Update
  End With

  If Err.Number <> 0 Then
    insertError = True
    Err.Clear
    Exit For
  End If

  adoRs.Close
  Set adoRs = Nothing
Next

'// 트랜잭션 완료 처리
If insertError Then
  '// 롤백 - INSERT 중 오류 발생
  dbCon.RollbackTrans

  '// 전체 실패로 변경 (응답 재생성)
  For i = 0 To orderCount - 1
    orderResult = "{" & _
      """order_no"":""" & JsonEncode(validationResults(i, 0)) & """," & _
      """phone_no"":""" & JsonEncode(phone_no) & """," & _
      """result_code"":""0017""," & _
      """message"":""트랜잭션오류""" & _
      "}"
    resultArray(i) = orderResult
  Next
  successCount = 0
  failCount = orderCount
Else
  '// 커밋 - 전체 성공
  dbCon.CommitTrans
End If
```

### 4.4 SMS 발송 조건 변경

```vbscript
'// ========================================
'// SMS/MMS 발송 (전체 성공 시에만)
'// ========================================

'// 변경 전: If req_type = "SMS" Or req_type = "KTK" Then
'// 변경 후: 성공 조건 추가
If (req_type = "SMS" Or req_type = "KTK") And failCount = 0 Then
  '// SMS 발송 로직 (기존과 동일)
  '// ...
End If
```

---

## 5. 에러 코드

### 5.1 기존 에러 코드 (변경 없음)

| 코드 | 메시지 | 설명 |
|------|--------|------|
| 0000 | 등록성공 | 주문 등록 성공 |
| 0002 | 주문번호누락 | order_no 필드 누락 |
| 0007 | 상품명누락 | cc_pord_desc 필드 누락 |
| 0008 | 결제금액누락 | amount 필드 누락 |
| 0011 | 거래번호중복 | terminal_id + order_no 중복 |

### 5.2 신규 에러 코드 (선택 사항)

| 코드 | 메시지 | 설명 |
|------|--------|------|
| 0017 | 트랜잭션오류 | DB INSERT 중 오류로 전체 롤백됨 (Phase 2에서만 발생) |

> **참고**: 0017은 Phase 2에서 예기치 않은 DB 오류 발생 시에만 사용됨.
> 일반적인 검증 실패는 기존 에러 코드 그대로 사용.

---

## 6. 구현 계획

### 6.1 수정 대상 파일
- `dev/db/kicc_ars_order_v3_batch.asp`

### 6.2 수정 영역

| 순서 | 영역 | 수정 내용 |
|------|------|----------|
| 1 | 라인 469-476 | 검증 결과 배열 선언 추가 |
| 2 | 라인 486-587 | Phase 1 (검증 전용)으로 변경, INSERT 제거 |
| 3 | 라인 587 이후 | 검증 실패 시 조기 응답 반환 로직 추가 |
| 4 | 라인 587 이후 | Phase 2 (트랜잭션 INSERT) 추가 |
| 5 | 라인 599 | SMS 발송 조건에 전체 성공 체크 추가 |

### 6.3 테스트 시나리오

| 시나리오 | 입력 | 기대 응답 | DB 등록 |
|----------|------|----------|---------|
| TC01 | 3건 모두 유효 | success=3, fail=0 | 3건 등록 |
| TC02 | 3건 중 1건 중복 | success=2, fail=1 | **0건 등록** |
| TC03 | 3건 중 1건 필수값 누락 | success=2, fail=1 | **0건 등록** |
| TC04 | 3건 중 2건 실패 | success=1, fail=2 | **0건 등록** |
| TC05 | 1건만 요청 (성공) | success=1, fail=0 | 1건 등록 |
| TC06 | 1건만 요청 (실패) | success=0, fail=1 | 0건 등록 |

---

## 7. 위험 요소 및 대응

### 7.1 클라이언트 호환성
- **응답 형식**: 기존과 100% 동일 → 클라이언트 수정 불필요
- **동작 변경**: `fail > 0`이면 실제 DB 등록이 없음을 인지해야 함
- **권장사항**: 클라이언트에 All-or-Nothing 정책 안내 필요

### 7.2 성능 고려사항
- **Phase 1 검증**: 주문 수만큼 SELECT 쿼리 실행 (현재와 동일)
- **Phase 2 INSERT**: 트랜잭션 사용으로 약간의 오버헤드 발생
- **영향**: 50건 이하 배치에서는 체감 차이 미미

### 7.3 롤백 전략
- **문제 발생 시**: 기존 파일 복구로 즉시 롤백 가능
- **백업**: 수정 전 파일 백업 필수

---

## 8. 문서 업데이트

### 8.1 수정 필요 파일
- `CLAUDE.md` - All-or-Nothing 동작 방식 설명 추가

### 8.2 업데이트 내용
1. 배치 처리 정책 변경 설명 추가
2. "1건이라도 실패 시 전체 등록 취소" 명시

---

## 9. 결론

### 9.1 변경 요약
| 항목 | AS-IS | TO-BE |
|------|-------|-------|
| 처리 방식 | 부분 성공 허용 | All-or-Nothing |
| 트랜잭션 | 미사용 | 사용 |
| 1건 실패 시 | 나머지 성공건 등록 | **전체 등록 취소** |
| 응답 형식 | 개별 결과 반환 | **기존과 동일** |
| SMS 발송 | 조건부 발송 | 전체 성공 시에만 |

### 9.2 핵심 포인트
> **응답은 기존과 동일, DB 등록만 All-or-Nothing**

- 클라이언트는 기존 응답 파싱 로직 변경 불필요
- `fail > 0`인 경우 DB에는 아무것도 등록되지 않음
- 성공/실패 카운트는 "검증 결과"를 의미 (실제 등록 건수와 다를 수 있음)

### 9.3 구현 우선순위
1. **필수**: Phase 1/2 분리 로직 구현
2. **필수**: 트랜잭션 적용
3. **필수**: SMS 발송 조건 수정 (전체 성공 시에만)
4. **선택**: 에러 코드 0017 추가 (트랜잭션 오류용)
