# TAS 메시징 서비스 연동 설계 문서

## 1. 개요

### 1.1 목적
기존 INFOBANK 방식의 SMS/MMS 발송 로직을 TAS(휴머스온) API 방식으로 전환하여 메시지 발송 서비스를 개선합니다.

### 1.2 범위
- **대상 파일**: `dev/db/kicc_ars_order_v3_batch.asp`
- **변경 영역**: SMS/MMS/카카오 알림톡 발송 로직 (669-768 라인)
- **지원 채널**: SMS, LMS, 카카오 알림톡 (KTK → KA 매핑)

### 1.3 TAS API 정보
| 항목 | 값 |
|------|-----|
| SMS/LMS 발송 URL | `https://api.tason.com/tas-api/send` |
| 알림톡 발송 URL | `https://api.tason.com/tas-api/kakaosend` |
| 결과 조회 URL | `https://api.tason.com/tas-api/result` |
| 인코딩 | UTF-8 |
| Content-Type | application/json |

---

## 2. 현재 시스템 분석

### 2.1 기존 INFOBANK 방식
```
발송 요청 → em_smt_tran/em_mmt_tran 테이블 INSERT → INFOBANK 에이전트가 폴링하여 발송
```

**특징**:
- DB 직접 INSERT 방식
- 80자 기준으로 SMS/MMS 구분
- `strConnectSMS` 연결 문자열 사용 (imds 데이터베이스)

### 2.2 기존 코드 위치
| 라인 | 내용 |
|------|------|
| 669-768 | SMS/MMS 발송 로직 |
| 680-688 | SMS 메시지 생성 |
| 693-695 | SMS/MMS 길이 판단 (80자 기준) |
| 700-746 | MMS 발송 (em_mmt_tran) |
| 748-764 | SMS 발송 (em_smt_tran) |

---

## 3. TAS 연동 설계

### 3.1 서비스 제공자 상수 정의
파일 상단에 다음 상수를 정의하여 INFOBANK/TAS 간 전환 가능하도록 합니다:

```asp
'// ========================================
'// SMS 발송 서비스 제공자 설정
'// ========================================
'// INFOBANK: 기존 DB INSERT 방식
'// TAS: 휴머스온 REST API 방식
Const SMS_PROVIDER = "TAS"

'// TAS API 설정 (SMS_PROVIDER = "TAS" 일 때 사용)
Const TAS_API_URL = "https://api.tason.com/tas-api/send"
Const TAS_KAKAO_API_URL = "https://api.tason.com/tas-api/kakaosend"
Const TAS_ID = "hyunia@arspg.com"
Const TAS_AUTH_KEY = "1IR274-VYTLDX-HUM3IS-SDMCBZ_1118"
Const TAS_DEFAULT_SENDER = "01024020684"
Const TAS_DEFAULT_SENDER_NAME = "안현"
```

### 3.2 request_type 매핑
| KICC request_type | TAS send_type | TAS API |
|-------------------|---------------|---------|
| SMS | SM (90바이트 이하) / LM (초과) | /tas-api/send |
| KTK | KA | /tas-api/kakaosend |
| ARS | - (SMS 발송 안 함) | - |

### 3.3 전화번호 형식 변환
TAS API는 국제 전화번호 형식을 요구합니다:
- **입력**: `01012345678`
- **출력**: `821012345678` (82 + 번호에서 앞자리 0 제거)

```asp
Function FormatPhoneForTAS(phoneNo)
  Dim result
  result = Replace(phoneNo, "-", "")
  If Left(result, 1) = "0" Then
    result = "82" & Mid(result, 2)
  End If
  FormatPhoneForTAS = result
End Function
```

### 3.4 TAS API 요청 함수

#### 3.4.1 SMS/LMS 발송
```asp
Function SendSMSViaTAS(recipientName, recipientPhone, content, sender, senderName, subject)
  Dim http, requestBody, response
  Dim sendType

  '// 90바이트 기준으로 SMS/LMS 구분
  If LenB(content) <= 90 Then
    sendType = "SM"  '// SMS
  Else
    sendType = "LM"  '// LMS
  End If

  '// JSON 요청 본문 생성
  requestBody = "{" & _
    """tas_id"":""" & TAS_ID & """," & _
    """send_type"":""" & sendType & """," & _
    """auth_key"":""" & TAS_AUTH_KEY & """," & _
    """data"":[{" & _
      """user_name"":""" & JsonEncode(recipientName) & """," & _
      """user_email"":""" & FormatPhoneForTAS(recipientPhone) & """," & _
      """map_content"":""" & JsonEncode(content) & """," & _
      """sender"":""" & sender & """," & _
      """sender_name"":""" & JsonEncode(senderName) & """," & _
      """subject"":""" & JsonEncode(subject) & """" & _
    "}]}"

  '// HTTP POST 요청
  Set http = Server.CreateObject("MSXML2.ServerXMLHTTP")
  http.Open "POST", TAS_API_URL, False
  http.setRequestHeader "Content-Type", "application/json; charset=UTF-8"
  http.Send requestBody

  response = http.responseText
  SendSMSViaTAS = response

  Set http = Nothing
End Function
```

#### 3.4.2 카카오 알림톡 발송
```asp
Function SendKakaoViaTAS(recipientName, recipientPhone, content, sender, senderName, templateCode)
  Dim http, requestBody, response

  '// JSON 요청 본문 생성
  requestBody = "{" & _
    """tas_id"":""" & TAS_ID & """," & _
    """send_type"":""KA""," & _
    """auth_key"":""" & TAS_AUTH_KEY & """," & _
    """data"":[{" & _
      """user_name"":""" & JsonEncode(recipientName) & """," & _
      """user_email"":""" & FormatPhoneForTAS(recipientPhone) & """," & _
      """map_content"":""" & JsonEncode(content) & """," & _
      """sender"":""" & sender & """," & _
      """sender_name"":""" & JsonEncode(senderName) & """," & _
      """template_code"":""" & templateCode & """" & _
    "}]}"

  '// HTTP POST 요청
  Set http = Server.CreateObject("MSXML2.ServerXMLHTTP")
  http.Open "POST", TAS_KAKAO_API_URL, False
  http.setRequestHeader "Content-Type", "application/json; charset=UTF-8"
  http.Send requestBody

  response = http.responseText
  SendKakaoViaTAS = response

  Set http = Nothing
End Function
```

---

## 4. 구현 계획

### 4.1 Phase 1: 상수 및 설정 추가
**위치**: 파일 상단 (44라인 이후)

1. SMS_PROVIDER 상수 정의
2. TAS API 연결 정보 상수 정의
3. INFOBANK/TAS 전환 가능한 구조 설정

### 4.2 Phase 2: 유틸리티 함수 추가
**위치**: 유틸리티 함수 영역 (100라인 부근)

1. `FormatPhoneForTAS()` - 전화번호 국제 형식 변환
2. `SendSMSViaTAS()` - TAS SMS/LMS 발송 함수
3. `SendKakaoViaTAS()` - TAS 카카오 알림톡 발송 함수

### 4.3 Phase 3: 발송 로직 수정
**위치**: SMS/MMS 발송 영역 (669-768라인)

기존 코드를 조건부 분기로 수정:
```asp
If SMS_PROVIDER = "TAS" Then
  '// TAS API 방식
  If req_type = "KTK" Then
    Call SendKakaoViaTAS(...)
  Else
    Call SendSMSViaTAS(...)
  End If
Else
  '// 기존 INFOBANK DB INSERT 방식 (유지)
  '// ... 기존 코드 ...
End If
```

### 4.4 Phase 4: 테스트
1. SMS_PROVIDER = "INFOBANK" 상태에서 기존 기능 정상 동작 확인
2. SMS_PROVIDER = "TAS" 변경 후 TAS API 연동 테스트
3. SMS/LMS 길이 구분 테스트
4. 카카오 알림톡 발송 테스트 (template_code 필요)

---

## 5. 데이터 매핑

### 5.1 SMS/LMS 파라미터 매핑
| KICC 변수 | TAS 파라미터 | 설명 |
|-----------|--------------|------|
| cc_name | user_name | 수신자명 |
| phone_no | user_email | 수신자 번호 (국제형식) |
| smsMsg | map_content | 발송 내용 |
| callback_no | sender | 발신자 번호 |
| terminal_nm | sender_name | 발신자명 |
| mms_subject | subject | 제목 (LMS 시) |

### 5.2 카카오 알림톡 파라미터 매핑
| KICC 변수 | TAS 파라미터 | 설명 |
|-----------|--------------|------|
| cc_name | user_name | 수신자명 |
| phone_no | user_email | 수신자 번호 (국제형식, 82로 시작) |
| smsMsg | map_content | 발송 내용 (템플릿과 일치해야 함) |
| callback_no | sender | 발신자 번호 |
| terminal_nm | sender_name | 발신자명 |
| (신규) | template_code | 카카오 템플릿 코드 |

---

## 6. 에러 처리

### 6.1 TAS API 응답 코드
| 응답 | 설명 |
|------|------|
| MEM_CNT > 0 | 발송 요청 성공 건수 |
| WRONG_DATA | 발송 실패 정보 |
| ERROR_CODE = 41 | 공통 에러 코드 |

### 6.2 주요 에러 메시지
| ERROR_MSG | 설명 |
|-----------|------|
| Required information | 필수값 누락 |
| Wrong AuthKey OR User id | 잘못된 인증 정보 |
| Low balance | 잔액 부족 |
| Wrong send type | 지원하지 않는 발송 채널 |

### 6.3 에러 처리 전략
```asp
Dim tasResponse
tasResponse = SendSMSViaTAS(...)

'// 응답 검증
If InStr(tasResponse, """ERROR_CODE""") > 0 Then
  '// API 에러 발생 - 로깅
  '// 필요 시 INFOBANK 폴백 고려
End If
```

---

## 7. 보안 고려사항

### 7.1 인증 정보 관리
- TAS_AUTH_KEY는 소스 코드에 하드코딩되어 있음
- **권장**: 운영 환경에서는 별도 설정 파일 또는 환경 변수 사용

### 7.2 HTTPS 통신
- TAS API는 HTTPS 사용으로 전송 구간 암호화
- MSXML2.ServerXMLHTTP는 기본적으로 SSL/TLS 지원

### 7.3 전화번호 형식
- 발신자 번호는 TAS 사이트에서 사전 인증 필요
- 미인증 발신자 번호 사용 시 발송 실패

---

## 8. 롤백 계획

### 8.1 즉시 롤백
SMS_PROVIDER 상수 값만 변경하면 즉시 롤백 가능:
```asp
Const SMS_PROVIDER = "INFOBANK"  '// TAS → INFOBANK 롤백
```

### 8.2 코드 롤백
기존 INFOBANK 로직은 삭제하지 않고 유지되므로, git revert로 전체 변경 사항 롤백 가능

---

## 9. 향후 개선 사항

### 9.1 단기
- [ ] TAS 발송 결과 로깅 테이블 추가
- [ ] 발송 실패 시 재시도 로직 구현
- [ ] 카카오 알림톡 템플릿 코드 관리 방안

### 9.2 장기
- [ ] TAS 인증 정보 외부 설정 파일로 분리
- [ ] 발송 결과 조회 API 연동 (/tas-api/result)
- [ ] 다중 발송 서비스 로드 밸런싱

---

## 10. 참고 문서

- TAS Messaging Service API Specification V1.2
- `dev/db/tas.env` - TAS 인증 정보
- `dev/db/kicc_ars_order_v3_batch.asp` - 대상 소스 파일
- `CLAUDE.md` - 프로젝트 문서

---

## 11. 구현 완료 내역

### 11.1 변경된 파일
- `dev/db/kicc_ars_order_v3_batch.asp`

### 11.2 추가된 상수 (45-58라인)
```asp
Const SMS_PROVIDER = "TAS"
Const TAS_API_URL = "https://api.tason.com/tas-api/send"
Const TAS_KAKAO_API_URL = "https://api.tason.com/tas-api/kakaosend"
Const TAS_ID = "hyunia@arspg.com"
Const TAS_AUTH_KEY = "1IR274-VYTLDX-HUM3IS-SDMCBZ_1118"
Const TAS_DEFAULT_SENDER = "01024020684"
Const TAS_DEFAULT_SENDER_NAME = "안현"
```

### 11.3 추가된 함수 (193-289라인)
1. **FormatPhoneForTAS(phoneNo)** - 전화번호 국제형식 변환
2. **SendSMSViaTAS(...)** - TAS SMS/LMS 발송
3. **SendKakaoViaTAS(...)** - TAS 카카오 알림톡 발송

### 11.4 수정된 로직 (778-915라인)
- SMS/MMS 발송 로직에 INFOBANK/TAS 분기 추가
- template_code 파라미터 파싱 추가 (336라인)

### 11.5 서비스 전환 방법
```asp
'// TAS 사용
Const SMS_PROVIDER = "TAS"

'// INFOBANK로 롤백
Const SMS_PROVIDER = "INFOBANK"
```

---

## 12. 변경 이력

| 버전 | 일자 | 변경 내용 | 작성자 |
|------|------|----------|--------|
| 1.0 | 2025-12-23 | 초안 작성 | Claude |
| 1.1 | 2025-12-23 | 구현 완료 | Claude |
