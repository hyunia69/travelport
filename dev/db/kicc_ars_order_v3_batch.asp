<%
  '// ================================================
  '// KICC ARS 배치 주문 처리 API - JSON Only
  '// ================================================
  '// JSON orders 배열 방식만 지원합니다.
  '//
  '// JSON 배치 주문 예시:
  '// {
  '//   "mode": "ars_data_add",
  '//   "terminal_id": "TERM001",
  '//   "request_type": "ARS",
  '//   "cc_name": "홍길동",
  '//   "phone_no": "01012345678",
  '//   "card_no": "1234567890123456",
  '//   "expire_date": "2512",
  '//   "install_month": "00",
  '//   "orders": [
  '//     {"order_no": "ORD001", "amount": 1000, "cc_pord_desc": "상품A"},
  '//     {"order_no": "ORD002", "amount": 2000, "cc_pord_desc": "상품B"}
  '//   ]
  '// }
  '// ================================================

  '// 한글 인코딩 설정 (UTF-8)
  Response.CharSet = "utf-8"
  Response.CodePage = 65001
  Response.ContentType = "application/json"

  '// OPTIONS 요청 처리 (CORS preflight)
  If UCase(Request.ServerVariables("REQUEST_METHOD")) = "OPTIONS" Then
    Response.Status = "200 OK"
    Response.End
  End If

  '// 에러 핸들링 활성화
  On Error Resume Next

  '// ADO 상수 직접 정의 (METADATA 대신)
  Const adCmdStoredProc = 4
  Const adVarChar = 200
  Const adParamInput = 1
  Const adOpenDynamic = 2
  Const adLockOptimistic = 3

  '// ========================================
  '// SMS 발송 서비스 제공자 설정
  '// ========================================
  '// INFOBANK: 기존 DB INSERT 방식 (em_smt_tran/em_mmt_tran 테이블)
  '// TAS: 휴머스온 REST API 방식 (https://api.tason.com)
  Const SMS_PROVIDER = "TAS"
  '//Const SMS_PROVIDER = "INFOBANK"

  '// TAS API 설정 (SMS_PROVIDER = "TAS" 일 때 사용)
  Const TAS_API_URL = "https://api.tason.com/tas-api/send"
  Const TAS_KAKAO_API_URL = "https://api.tason.com/tas-api/kakaosend"
  Const TAS_ID = "hyunia69@arspg.com"
  Const TAS_AUTH_KEY = "1IR274-VYTLDX-HUM3IS-SDMCBZ_1118"
  Const TAS_DEFAULT_SENDER = "0234906698"
  Const TAS_DEFAULT_SENDER_NAME = "다삼솔루션"
  Const TAS_KAKAO_TEMPLATE_CODE = "C_KK_013_02_73931"  '// 카카오 알림톡 템플릿 코드
%>
<%
  '// ========================================
  '// 유틸리티 함수
  '// ========================================

  '// 요청 바디 읽기 함수 (JSON 요청용)
  Function ReadRequestBody()
    Dim lngBytesCount, objStream
    lngBytesCount = Request.TotalBytes

    If lngBytesCount = 0 Then
      ReadRequestBody = ""
      Exit Function
    End If

    Set objStream = Server.CreateObject("ADODB.Stream")
    objStream.Type = 1  '// Binary
    objStream.Open
    objStream.Write Request.BinaryRead(lngBytesCount)
    objStream.Position = 0
    objStream.Type = 2  '// Text
    objStream.Charset = "utf-8"
    ReadRequestBody = objStream.ReadText
    objStream.Close
    Set objStream = Nothing
  End Function

  '// 간단한 JSON 값 추출 함수 (문자열과 숫자 값 모두 지원)
  Function ExtractJsonString(jsonText, fieldName)
    Dim pattern, matches, match, value
    Set regEx = New RegExp
    '// 문자열 값 (따옴표로 감싸진 값) 또는 숫자 값 모두 매칭
    regEx.Pattern = """" & fieldName & """\s*:\s*(?:""([^""]*)""|'([^']*)'|(\d+\.?\d*))"
    regEx.IgnoreCase = True
    regEx.Global = False

    Set matches = regEx.Execute(jsonText)
    If matches.Count > 0 Then
      Set match = matches(0)
      '// 첫 번째 서브매치 (큰따옴표 문자열)
      If match.SubMatches(0) <> "" Then
        ExtractJsonString = match.SubMatches(0)
      '// 두 번째 서브매치 (작은따옴표 문자열)
      ElseIf match.SubMatches(1) <> "" Then
        ExtractJsonString = match.SubMatches(1)
      '// 세 번째 서브매치 (숫자)
      ElseIf match.SubMatches(2) <> "" Then
        ExtractJsonString = match.SubMatches(2)
      Else
        ExtractJsonString = ""
      End If
    Else
      ExtractJsonString = ""
    End If
    Set regEx = Nothing
  End Function

  '// JSON orders 배열 파싱 함수
  Function ParseJsonOrders(jsonText)
    Dim pattern, matches, match, ordersJson
    Dim ordersList, i, orderItem
    Dim orderNoList, amountList, descList

    '// orders 배열 추출
    Set regEx = New RegExp
    regEx.Pattern = """orders""\s*:\s*\[([\s\S]*?)\]"
    regEx.IgnoreCase = True
    regEx.Global = False

    Set matches = regEx.Execute(jsonText)
    If matches.Count = 0 Then
      ParseJsonOrders = Array(Array(), Array(), Array())
      Exit Function
    End If

    ordersJson = matches(0).SubMatches(0)

    '// 각 주문 객체 추출
    Set regEx = New RegExp
    regEx.Pattern = "\{([^}]+)\}"
    regEx.IgnoreCase = True
    regEx.Global = True

    Set matches = regEx.Execute(ordersJson)

    If matches.Count = 0 Then
      ParseJsonOrders = Array(Array(), Array(), Array())
      Exit Function
    End If

    ReDim orderNoList(matches.Count - 1)
    ReDim amountList(matches.Count - 1)
    ReDim descList(matches.Count - 1)

    For i = 0 To matches.Count - 1
      orderItem = matches(i).Value
      orderNoList(i) = ExtractJsonString(orderItem, "order_no")
      amountList(i) = ExtractJsonString(orderItem, "amount")
      descList(i) = ExtractJsonString(orderItem, "cc_pord_desc")
    Next

    ParseJsonOrders = Array(orderNoList, amountList, descList)
    Set regEx = Nothing
  End Function

  '// JSON 인코딩 함수 (특수문자 이스케이프)
  Function JsonEncode(str)
    Dim result
    If IsNull(str) Or str = "" Then
      result = ""
    Else
      result = CStr(str)
      result = Replace(result, "\", "\\")
      result = Replace(result, """", "\""")
      result = Replace(result, vbCrLf, "\n")
      '// LF(Chr(10))만 포함된 줄바꿈도 반드시 이스케이프 (TAS JSON 파싱 400 방지)
      result = Replace(result, vbLf, "\n")
      result = Replace(result, vbCr, "\r")
      result = Replace(result, vbTab, "\t")
    End If
    JsonEncode = result
  End Function

  '// 입력 문자열에 포함된 JSON 이스케이프(\n, \r, \r\n, \t)를 실제 제어문자로 복원
  '// 예) "첫줄\n둘째줄"  ->  "첫줄" & vbLf & "둘째줄"
  '// 주의: 여기서는 줄바꿈/탭만 처리(역슬래시 자체(\\)는 건드리지 않음)
  Function DecodeControlEscapes(str)
    Dim result
    If IsNull(str) Or str = "" Then
      DecodeControlEscapes = ""
      Exit Function
    End If

    result = CStr(str)
    result = Replace(result, "\r\n", vbCrLf)
    result = Replace(result, "\n", vbLf)
    result = Replace(result, "\r", vbCr)
    result = Replace(result, "\t", vbTab)
    DecodeControlEscapes = result
  End Function

  '// 숫자를 천단위 콤마 포맷팅
  Function FormatNumberWithComma(num)
    Dim strNum, result, i, cnt
    strNum = CStr(num)
    result = ""
    cnt = 0
    For i = Len(strNum) To 1 Step -1
      cnt = cnt + 1
      result = Mid(strNum, i, 1) & result
      If cnt Mod 3 = 0 And i > 1 Then
        result = "," & result
      End If
    Next
    FormatNumberWithComma = result
  End Function

  '// JSON 배열 생성 함수
  Function BuildJsonArray(items)
    Dim i, jsonArray
    jsonArray = "["
    For i = 0 To UBound(items)
      If i > 0 Then jsonArray = jsonArray & ","
      jsonArray = jsonArray & items(i)
    Next
    jsonArray = jsonArray & "]"
    BuildJsonArray = jsonArray
  End Function

  '// ========================================
  '// TAS API 관련 함수
  '// ========================================

  '// 전화번호 정규화 (하이픈, 공백 제거만 수행)
  Function FormatPhoneForTAS(phoneNo)
    Dim result
    result = Replace(phoneNo, "-", "")
    result = Replace(result, " ", "")
    FormatPhoneForTAS = result
  End Function

  '// 전화번호를 카카오톡 국제 형식으로 변환 (82 + 앞자리 0 제거)
  Function FormatPhoneForKakao(phoneNo)
    Dim result
    result = Replace(phoneNo, "-", "")
    result = Replace(result, " ", "")
    '// 0으로 시작하면 82로 변환 (한국 국제전화 형식)
    If Left(result, 1) = "0" Then
      result = "82" & Mid(result, 2)
    End If
    FormatPhoneForKakao = result
  End Function

  '// TAS API를 통한 SMS/LMS 발송
  '// 반환값: TAS API 응답 JSON 문자열
  Function SendSMSViaTAS(recipientName, recipientPhone, content, sender, senderName, subject)
    Dim http, requestBody, response, sendType

    On Error Resume Next

    '// 90바이트 기준으로 SMS/LMS 구분 (TAS 기준)
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
        """sender"":""" & Replace(sender, "-", "") & """," & _
        """sender_name"":""" & JsonEncode(senderName) & """," & _
        """subject"":""" & JsonEncode(subject) & """" & _
      "}]}"

    '// HTTP POST 요청
    Set http = Server.CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.Open "POST", TAS_API_URL, False
    http.setRequestHeader "Content-Type", "application/json; charset=UTF-8"
    http.Send requestBody

    response = http.responseText
    SendSMSViaTAS = response

    Set http = Nothing

    If Err.Number <> 0 Then
      SendSMSViaTAS = "{""ERROR_CODE"":""99"",""ERROR_MSG"":""HTTP 요청 실패: " & Err.Description & """}"
      Err.Clear
    End If
  End Function

  '// TAS API를 통한 카카오 알림톡 발송
  '// 반환값: TAS API 응답 JSON 문자열
  Function SendKakaoViaTAS(recipientName, recipientPhone, content, sender, senderName, templateCode)
    Dim http, requestBody, response

    On Error Resume Next

    '// JSON 요청 본문 생성
    requestBody = "{" & _
      """tas_id"":""" & TAS_ID & """," & _
      """send_type"":""KA""," & _
      """auth_key"":""" & TAS_AUTH_KEY & """," & _
      """data"":[{" & _
        """user_name"":""" & JsonEncode(recipientName) & """," & _
        """user_email"":""" & FormatPhoneForKakao(recipientPhone) & """," & _
        """map_content"":""" & JsonEncode(content) & """," & _
        """sender"":""" & Replace(sender, "-", "") & """," & _
        """sender_name"":""" & JsonEncode(senderName) & """," & _
        """template_code"":""" & templateCode & """" & _
      "}]}"

    '// 디버깅용 요청 본문 저장 (전역 변수)
    tasRequestBody = requestBody

    '// HTTP POST 요청
    Set http = Server.CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.Open "POST", TAS_KAKAO_API_URL, False
    http.setRequestHeader "Content-Type", "application/json; charset=UTF-8"
    http.Send requestBody

    response = http.responseText
    SendKakaoViaTAS = response

    Set http = Nothing

    If Err.Number <> 0 Then
      SendKakaoViaTAS = "{""ERROR_CODE"":""99"",""ERROR_MSG"":""HTTP 요청 실패: " & Err.Description & """}"
      Err.Clear
    End If
  End Function

  '// ========================================
  '// JSON 요청 파싱
  '// ========================================

  Dim jsonBody, parsedOrders
  Dim strMode, terminal_id, req_type, alert_show, verify_num
  Dim cc_name, phone_no, cc_email
  Dim card_no, expire_date, install_month, sms_message, mms_subject
  Dim orderNoArray, amountArray, productDescArray, orderCount

  Dim strConnect, strConnectSMS
  strConnect="Provider=SQLOLEDB.1;Password=medi@ford;Persist Security Info=True;User ID=sa;Initial Catalog=arspg_web;Data Source=211.196.157.119"
  strConnectSMS="Provider=SQLOLEDB.1;Password=imds@00;Persist Security Info=True;User ID=imds;Initial Catalog=imds;Data Source=211.196.157.121"

  jsonBody = ReadRequestBody()

  If jsonBody = "" Then
    Dim emptyErrorJson
    emptyErrorJson = "{" & _
                """batch_summary"":{""total"":0,""success"":0,""fail"":0}," & _
                """req_result"":[{" & _
                """order_no"":""""," & _
                """phone_no"":""""," & _
                """result_code"":""0001""," & _
                """message"":""JSON 요청 바디가 비어있습니다""" & _
                "}]}"
    response.write emptyErrorJson
    response.end
  End If

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
  '// Swagger/클라이언트에서 "...\n..." 형태로 보낸 경우 실제 개행으로 복원
  sms_message = DecodeControlEscapes(ExtractJsonString(jsonBody, "sms_message"))
  mms_subject = DecodeControlEscapes(ExtractJsonString(jsonBody, "mms_subject"))
  '// 여행사/항공 SMS 자동 생성용 파라미터
  agency_name = ExtractJsonString(jsonBody, "agency_name")
  reservation_no = ExtractJsonString(jsonBody, "reservation_no")

  '// 배치 데이터 처리 (orders 배열)
  parsedOrders = ParseJsonOrders(jsonBody)
  orderNoArray = parsedOrders(0)
  amountArray = parsedOrders(1)
  productDescArray = parsedOrders(2)

  If UBound(orderNoArray) >= 0 And orderNoArray(0) <> "" Then
    orderCount = UBound(orderNoArray) + 1
  Else
    orderCount = 0
  End If

  '// ========================================
  '// 기본 검증
  '// ========================================

  Dim errorJson, errorOrderCount

  If strMode <> "ars_data_add" Then
    If orderCount > 0 Then
      errorOrderCount = orderCount
    Else
      errorOrderCount = 1
    End If
    errorJson = "{" & _
                """batch_summary"":{""total"":" & errorOrderCount & ",""success"":0,""fail"":" & errorOrderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""""," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0001""," & _
                """message"":""전송데이터구분오류""" & _
                "}]}"
    response.write errorJson
    response.end
  End if

  If orderCount = 0 Or (UBound(orderNoArray) = 0 And orderNoArray(0) = "") Then
    errorJson = "{" & _
                """batch_summary"":{""total"":0,""success"":0,""fail"":0}," & _
                """req_result"":[{" & _
                """order_no"":""""," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0002""," & _
                """message"":""주문번호누락 (orders 배열 필요)""" & _
                "}]}"
    response.write errorJson
    response.end
  End if

  If terminal_id = "" Then
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0003""," & _
                """message"":""가맹점터미널ID누락""" & _
                "}]}"
    response.write errorJson
    response.end
  End if

  If req_type = "" Then
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0004""," & _
                """message"":""ARS타입누락""" & _
                "}]}"
    response.write errorJson
    response.end
  End if

  If card_no = "" Then
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0005""," & _
                """message"":""카드번호누락""" & _
                "}]}"
    response.write errorJson
    response.end
  End if

  If cc_name = "" Then
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0006""," & _
                """message"":""고객명누락""" & _
                "}]}"
    response.write errorJson
    response.end
  End if

  If phone_no = "" Then
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""""," & _
                """result_code"":""0009""," & _
                """message"":""전화번호누락""" & _
                "}]}"
    response.write errorJson
    response.end
  End if

  If expire_date = "" Then
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0014""," & _
                """message"":""유효기간누락""" & _
                "}]}"
    response.write errorJson
    response.end
  End if

  If install_month = "" Then
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0015""," & _
                """message"":""할부개월수누락""" & _
                "}]}"
    response.write errorJson
    response.end
  End if

  '// SMS/KTK 타입일 때, sms_message가 없으면 agency_name, reservation_no 필수 검증
  If (req_type = "SMS" Or req_type = "KTK") And sms_message = "" Then
    If agency_name = "" Then
      errorJson = "{" & _
                  """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                  """req_result"":[{" & _
                  """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                  """phone_no"":""" & JsonEncode(phone_no) & """," & _
                  """result_code"":""0016""," & _
                  """message"":""여행사명누락 (sms_message 미제공 시 필수)""" & _
                  "}]}"
      response.write errorJson
      response.end
    End If

    If reservation_no = "" Then
      errorJson = "{" & _
                  """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                  """req_result"":[{" & _
                  """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                  """phone_no"":""" & JsonEncode(phone_no) & """," & _
                  """result_code"":""0018""," & _
                  """message"":""예약번호누락 (sms_message 미제공 시 필수)""" & _
                  "}]}"
      response.write errorJson
      response.end
    End If
  End If

  '// 배열 길이 검증
  If UBound(amountArray) + 1 <> orderCount Then
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0012""," & _
                """message"":""주문건수와 금액건수 불일치""" & _
                "}]}"
    response.write errorJson
    response.end
  End If

  If UBound(productDescArray) + 1 <> orderCount Then
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0013""," & _
                """message"":""주문건수와 상품명건수 불일치""" & _
                "}]}"
    response.write errorJson
    response.end
  End If

  '// ========================================
  '// 가맹점 정보 가져오기
  '// ========================================

  Dim cmd, rs, terminal_nm, terminal_pw, ars_dnis, admin_id, admin_name

  set cmd = Server.CreateObject("ADODB.Command")
  with cmd
      .ActiveConnection = strConnect
      .CommandType = adCmdStoredProc
      .CommandTimeout = 60
      .CommandText = "sp_getKiccShopInfo"
      .Parameters.Append .CreateParameter("@TERMINAL_ID", adVarChar, adParamInput, 20, terminal_id)
      set rs = .Execute
  end with
  set cmd = nothing

  If Not rs.EOF Then
    terminal_nm   = trim(rs("terminal_nm"))
    terminal_id   = trim(rs("terminal_id"))
    terminal_pw   = trim(rs("terminal_pw"))
    ars_dnis      = trim(rs("ars_dnis"))
    admin_id      = trim(rs("admin_id"))
    admin_name    = trim(rs("admin_name"))
  Else
    errorJson = "{" & _
                """batch_summary"":{""total"":" & orderCount & ",""success"":0,""fail"":" & orderCount & "}," & _
                """req_result"":[{" & _
                """order_no"":""" & JsonEncode(orderNoArray(0)) & """," & _
                """phone_no"":""" & JsonEncode(phone_no) & """," & _
                """result_code"":""0010""," & _
                """message"":""가맹점터미널ID불일치""" & _
                "}]}"
    response.write errorJson
    response.end
  End if
  rs.close
  set rs = nothing

  '// ========================================
  '// 배치 인증번호 생성 (모든 타입 공통)
  '// ========================================
  '// 위치: 주문 처리 루프 진입 전 (배치당 1회만 실행)
  '// 모든 타입(ARS, SMS, KTK)에 대해 동일하게 인증번호 생성

  Dim maxcode, tempCode, j, arsRs
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

  '// ========================================
  '// 데이터베이스 연결
  '// ========================================

  Dim dbCon
  Set dbCon = Server.CreateObject("ADODB.Connection")
  dbCon.Open strConnect

  '// ========================================
  '// All-or-Nothing 트랜잭션 처리
  '// ========================================
  '// Phase 1: 사전 검증 (INSERT 없음)
  '// Phase 2: 전체 성공 시에만 일괄 INSERT
  '// ========================================

  '// 배치 처리 결과 저장
  Dim resultArray()
  ReDim resultArray(orderCount - 1)
  Dim successCount, failCount
  successCount = 0
  failCount = 0

  '// 검증 결과 임시 저장 배열
  '// validationResults(i, 0) = order_no
  '// validationResults(i, 1) = result_code ("0000" = 통과, 기타 = 실패)
  '// validationResults(i, 2) = message
  '// validationResults(i, 3) = amount
  '// validationResults(i, 4) = cc_pord_desc
  Dim validationResults()
  ReDim validationResults(orderCount - 1, 4)
  Dim validationFailCount
  validationFailCount = 0

  Dim i, currentOrderNo, currentAmount, currentProductDesc
  Dim callback_no, qry, mx_cnt
  Dim orderResult, adoRs

  '// ========================================
  '// Phase 1: 사전 검증 (INSERT 없음)
  '// ========================================

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
      qry = "SELECT count(order_no) cnt FROM KICC_SHOP_ORDER where terminal_id = '"& terminal_id &"' and order_no = '"& currentOrderNo &"'"
      Set rs = dbCon.Execute(qry)
      mx_cnt = rs("cnt")
      rs.close
      set rs = nothing

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
      """order_no"":""" & JsonEncode(validationResults(i, 0)) & """," & _
      """phone_no"":""" & JsonEncode(phone_no) & """," & _
      """result_code"":""" & validationResults(i, 1) & """," & _
      """message"":""" & JsonEncode(validationResults(i, 2)) & """" & _
      "}"
    resultArray(i) = orderResult
  Next

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
    Dim earlyJsonResponse
    earlyJsonResponse = "{" & _
      """batch_summary"":{" & _
      """total"":" & orderCount & "," & _
      """success"":" & successCount & "," & _
      """fail"":" & failCount & _
      "}," & _
      """req_result"":" & BuildJsonArray(resultArray) & _
      "}"

    response.write earlyJsonResponse
    response.end
  End If

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
    with adoRs
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

  '// 데이터베이스 연결 종료
  dbCon.close
  Set dbCon = nothing

  '// ========================================
  '// SMS/MMS/알림톡 발송 (조건부 실행)
  '// ========================================
  '// 위치: 주문 루프 종료 후 (배치당 1회만 실행)
  '// SMS/KTK 타입 + 전체 성공 시에만 발송 (All-or-Nothing 정책)

  Dim tasDebugInfo  '// 디버깅용 TAS 응답 저장 (블록 밖에서 선언)
  Dim kakaoMessage  '// 디버깅용 카카오 메시지 저장
  Dim tasRequestBody  '// 디버깅용 TAS API 요청 본문 저장
  tasDebugInfo = ""
  kakaoMessage = ""
  tasRequestBody = ""

  If (req_type = "SMS" Or req_type = "KTK") And failCount = 0 Then
    '// 콜백번호 설정
    If ars_dnis <> "" Then
      callback_no = "02-3490-" & ars_dnis
    Else
      callback_no = "02-3490-4411"
    End if

    '// 배치 전체 금액 합계 계산
    Dim totalAmount, k
    totalAmount = 0
    For k = 0 To orderCount - 1
      If IsNumeric(amountArray(k)) Then
        totalAmount = totalAmount + CLng(amountArray(k))
      End If
    Next

    '// SMS/MMS 메시지 생성
    Dim smsMsg, msgLength, useMMS, smsRs, tasResponse

    If sms_message <> "" Then
      '// 사용자 정의 메시지
      smsMsg = sms_message
    ElseIf agency_name <> "" And reservation_no <> "" Then
      '// 여행사/항공 자동 메시지 생성 (항공사명: 대한항공 고정)
      '// 카카오 알림톡 템플릿(C_KK_013_02_73931)과 정확히 일치해야 함
      smsMsg = "안녕하세요 고객님," & vbLf & _
               agency_name & "여행사 입니다. 대한항공 ARS 결제 안내드립니다." & vbLf & _
               vbLf & _
               "승객명 : " & cc_name & vbLf & _
               "결제금액 : " & FormatNumberWithComma(totalAmount) & "원" & vbLf & _
               "예약번호 : " & reservation_no & vbLf & _
               "ARS 진행하기 : 02-3490-6698" & vbLf & _
               "본 문자 수신 하신 후 1시간 이내에 ARS 결제를 진행해 주시기 바랍니다." & vbLf & _
               "※ ARS 접수건은 최대 당일 23시 50분까지 유효합니다."
    Else
      '// 기존 기본 형식 (폴백)
      smsMsg = cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
    End If
    '//smsMsg = smsMsg & callback_no & " 로전화주십시오"

    '// ========================================
    '// SMS 발송 서비스 분기 (TAS / INFOBANK)
    '// ========================================

    If SMS_PROVIDER = "TAS" Then
      '// ========================================
      '// TAS API 방식 (휴머스온 REST API)
      '// ========================================

      If req_type = "KTK" Then
        '// 카카오 알림톡 발송 (상수 TAS_KAKAO_TEMPLATE_CODE 사용)
        kakaoMessage = smsMsg  '// 디버깅용 메시지 저장
        tasResponse = SendKakaoViaTAS(cc_name, phone_no, smsMsg, TAS_DEFAULT_SENDER, TAS_DEFAULT_SENDER_NAME, TAS_KAKAO_TEMPLATE_CODE)
      Else
        '// SMS/LMS 발송 (90바이트 기준 자동 구분)
        tasResponse = SendSMSViaTAS(cc_name, phone_no, smsMsg, TAS_DEFAULT_SENDER, TAS_DEFAULT_SENDER_NAME, mms_subject)
      End If

      '// 디버깅용 TAS 응답 저장
      tasDebugInfo = tasResponse

    Else
      '// ========================================
      '// INFOBANK 방식 (기존 DB INSERT 방식)
      '// ========================================

      '// 메시지 길이 체크: 80자 이상이면 MMS, 미만이면 SMS
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
          .Fields("mt_refkey")       = terminal_id & "@BATCH"  '// 배치 단위 식별
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
            .Fields("mt_refkey")       = terminal_id & "@BATCH"  '// 배치 단위 식별
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
          .Fields("mt_refkey")       = terminal_id & "@BATCH"  '// 배치 단위 식별
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
    End If  '// End SMS_PROVIDER 분기

  End If

  '// ========================================
  '// 결과 반환 (JSON)
  '// ========================================

  If alert_show = "Y" Or alert_show = "" Then
    '// JSON 응답 생성
    Dim jsonResponse
    jsonResponse = "{" & _
                   """batch_summary"":{" & _
                   """total"":" & orderCount & "," & _
                   """success"":" & successCount & "," & _
                   """fail"":" & failCount & _
                   "}," & _
                   """req_result"":" & BuildJsonArray(resultArray) & "," & _
                   """tas_debug"":""" & JsonEncode(tasDebugInfo) & """," & _
                   """kakao_message"":""" & JsonEncode(kakaoMessage) & """," & _
                   """tas_request"":""" & JsonEncode(tasRequestBody) & """" & _
                   "}"

    response.write jsonResponse
    response.end
  End if
%>
