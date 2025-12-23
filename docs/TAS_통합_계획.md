# TAS 메시지 서비스 통합 계획

## 목표
`kicc_ars_order_v3_batch.asp`의 SMS/MMS 발송 로직을 TAS API로 변경하고, 기존 INFOBANK 로직도 유지하여 설정으로 선택 가능하도록 구현

## 사용자 확인 사항
- **KTK(알림톡)**: 템플릿 코드 있음 → 알림톡 API 사용
- **폴백**: TAS 실패 시 폴백 없음 (실패 처리)
- **발신번호**: tas.env 값 사용 (`01024020684`)

## 수정 대상 파일
- `C:\Work\dasam\code\claude\travelport\dev\db\kicc_ars_order_v3_batch.asp`

## 구현 계획

### Phase 1: 상수 및 설정 정의 (라인 44 이후)
파일 상단에 서비스 제공자 선택 상수 추가:

```asp
'// ========================================
'// SMS 서비스 제공자 설정
'// ========================================
Const SMS_PROVIDER_INFOBANK = "INFOBANK"
Const SMS_PROVIDER_TAS = "TAS"

'// 현재 사용할 SMS 서비스 제공자 선택
Const CURRENT_SMS_PROVIDER = "TAS"  '// "INFOBANK" 또는 "TAS"

'// TAS API 설정 (tas.env 참조)
Const TAS_API_URL = "https://api.tason.com/tas-api/send"
Const TAS_KAKAO_API_URL = "https://api.tason.com/tas-api/kakaosend"
Const TAS_ID = "hyunia@arspg.com"
Const TAS_AUTH_KEY = "1IR274-VYTLDX-HUM3IS-SDMCBZ_1118"
Const TAS_DEFAULT_SENDER = "01024020684"
Const TAS_DEFAULT_SENDER_NAME = "안현"

'// 카카오 알림톡 템플릿 코드 (TAS 사이트에서 등록)
Const TAS_KAKAO_TEMPLATE_CODE = ""  '// TODO: 실제 템플릿 코드 입력
```

### Phase 2: TAS API 호출 함수 구현 (유틸리티 함수 섹션에 추가)

#### 2-1. HTTP POST 요청 함수
```asp
Function SendHttpPost(url, jsonBody)
  Dim xmlHttp, response
  Set xmlHttp = Server.CreateObject("MSXML2.ServerXMLHTTP.6.0")
  xmlHttp.Open "POST", url, False
  xmlHttp.setRequestHeader "Content-Type", "application/json; charset=utf-8"
  xmlHttp.send jsonBody
  response = xmlHttp.responseText
  SendHttpPost = response
  Set xmlHttp = Nothing
End Function
```

#### 2-2. TAS SMS/LMS 발송 함수
```asp
Function SendViaTAS(sendType, recipientName, recipientPhone, content, senderPhone, senderName)
  '// sendType: "SM" (SMS), "LM" (LMS)
  '// 반환: JSON 응답 문자열
End Function
```

#### 2-3. TAS 카카오 알림톡 발송 함수
```asp
Function SendKakaoViaTAS(recipientName, recipientPhone, content, senderPhone, senderName, templateCode)
  '// 알림톡 발송
  '// 반환: JSON 응답 문자열
End Function
```

### Phase 3: SMS/MMS 발송 로직 수정 (라인 669-768)

기존 로직을 조건문으로 감싸고 TAS 로직 추가:

```asp
If CURRENT_SMS_PROVIDER = SMS_PROVIDER_TAS Then
  '// TAS API 사용
  If req_type = "KTK" Then
    '// 카카오 알림톡 API 사용
    tasResponse = SendKakaoViaTAS(cc_name, phone_no, smsMsg, TAS_DEFAULT_SENDER, TAS_DEFAULT_SENDER_NAME, TAS_KAKAO_TEMPLATE_CODE)
  Else
    '// SMS 또는 LMS (메시지 길이에 따라 자동 선택)
    '// 한글 기준 약 45자 = 90바이트
    If msgLength <= 45 Then
      tasResponse = SendViaTAS("SM", cc_name, phone_no, smsMsg, TAS_DEFAULT_SENDER, TAS_DEFAULT_SENDER_NAME)
    Else
      tasResponse = SendViaTAS("LM", cc_name, phone_no, smsMsg, TAS_DEFAULT_SENDER, TAS_DEFAULT_SENDER_NAME)
    End If
  End If
  '// TAS 실패 시 폴백 없음 (실패 처리)
Else
  '// 기존 INFOBANK 로직 (em_smt_tran, em_mmt_tran 테이블 INSERT)
  '// ... 기존 코드 유지 ...
End If
```

### Phase 4: 타입별 처리 상세

#### SMS 타입 (req_type = "SMS")
- 메시지 90바이트 이하 → TAS `SM` (SMS)
- 메시지 90바이트 초과 → TAS `LM` (LMS)

#### KTK 타입 (req_type = "KTK")
- 카카오 알림톡 API 사용 (`/tas-api/kakaosend`)
- 템플릿 코드 사용 (`TAS_KAKAO_TEMPLATE_CODE` 상수)
- **주의**: TAS 사이트에서 템플릿 사전 등록 및 승인 필요

## TAS API 요청/응답 형식

### SMS/LMS 요청
```json
{
  "tas_id": "hyunia@arspg.com",
  "send_type": "SM",
  "auth_key": "1IR274-VYTLDX-HUM3IS-SDMCBZ_1118",
  "data": [{
    "user_name": "수신자명",
    "user_email": "01012345678",
    "map_content": "메시지 내용",
    "sender": "01024020684",
    "sender_name": "안현"
  }]
}
```

### 카카오 알림톡 요청
```json
{
  "tas_id": "hyunia@arspg.com",
  "send_type": "KA",
  "auth_key": "1IR274-VYTLDX-HUM3IS-SDMCBZ_1118",
  "data": [{
    "user_name": "수신자명",
    "user_email": "8201012345678",
    "map_content": "메시지 내용 (템플릿과 동일해야 함)",
    "sender": "01024020684",
    "sender_name": "안현",
    "template_code": "템플릿코드"
  }]
}
```

### 응답 처리
```json
{
  "MEM_CNT": 1,
  "WRONG_DATA": []
}
```

| 파라미터 | 설명 |
|----------|------|
| MEM_CNT | 발송요청 성공된 건수 |
| WRONG_DATA | 실패 데이터 배열 |
| ERROR_CODE | 에러코드 (41: 공통 에러) |
| ERROR_MSG | 에러 상세 내용 |

### 에러 메시지 종류
- `Required information`: 필수값 누락
- `Wrong AuthKey OR User id`: 잘못된 아이디 혹은 인증키
- `Error check balance`: 잔액 체크 중 에러
- `Low balance`: 잔액 없음
- `Wrong send type`: 지원하지 않는 발송 채널
- `Low expected balance`: 발송 건수 대비 잔액 부족

## 구현 순서 요약
1. 상수 정의 추가 (라인 44 이후)
2. HTTP POST 함수 추가 (유틸리티 섹션)
3. TAS SMS/LMS 발송 함수 추가
4. TAS 알림톡 발송 함수 추가
5. 기존 발송 로직을 조건문으로 감싸기 (라인 669-768)
6. INFOBANK 로직 보존

## 체크리스트
- [ ] SMS_PROVIDER 상수 정의
- [ ] TAS API 인증 정보 상수 정의
- [ ] SendHttpPost 함수 구현
- [ ] SendViaTAS 함수 구현
- [ ] SendKakaoViaTAS 함수 구현
- [ ] SMS/LMS 발송 분기 로직 구현
- [ ] KTK(알림톡) 분기 로직 구현
- [ ] 기존 INFOBANK 로직 보존
- [ ] 에러 처리 추가
- [ ] UTF-8 인코딩 유지 확인

## 주의사항
1. **Classic ASP에서 HTTP 요청**: `MSXML2.ServerXMLHTTP.6.0` 사용
2. **UTF-8 인코딩**: TAS API는 UTF-8 기본, ASP 파일도 UTF-8 유지
3. **알림톡 템플릿**: KTK 타입 사용 시 TAS 사이트에서 템플릿 사전 등록 필요
4. **발신번호 인증**: TAS 사이트에서 발신번호 인증 필수
5. **메시지 길이**: SMS 90바이트, LMS 2000바이트 제한
