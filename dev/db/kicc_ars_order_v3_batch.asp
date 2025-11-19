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

  '// CORS 헤더는 web.config에서 처리 (중복 방지)
  '// OPTIONS 메서드 처리는 web.config와 IIS에서 자동 처리
%>
<!--METADATA TYPE="typelib" FILE="C:\program Files\Common Files\System\ado\msado15.dll"-->
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
      result = Replace(result, vbCr, "\r")
      result = Replace(result, vbTab, "\t")
    End If
    JsonEncode = result
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
  sms_message = ExtractJsonString(jsonBody, "sms_message")
  mms_subject = ExtractJsonString(jsonBody, "mms_subject")

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

  '// 배치 처리 결과 저장
  Dim resultArray()
  ReDim resultArray(orderCount - 1)
  Dim resultIndex
  resultIndex = 0
  Dim successCount, failCount
  successCount = 0
  failCount = 0

  '// ========================================
  '// 각 주문건 처리 루프
  '// ========================================

  Dim i, currentOrderNo, currentAmount, currentProductDesc
  Dim callback_no, qry, mx_cnt
  Dim orderResult, adoRs

  For i = 0 To orderCount - 1
    currentOrderNo = Trim(orderNoArray(i))
    currentAmount = Trim(amountArray(i))
    currentProductDesc = Trim(productDescArray(i))

    '// 개별 주문번호 검증
    If currentOrderNo = "" Then
      orderResult = "{" & _
                    """order_no"":""""," & _
                    """phone_no"":""" & JsonEncode(phone_no) & """," & _
                    """result_code"":""0002""," & _
                    """message"":""주문번호누락""" & _
                    "}"
      resultArray(resultIndex) = orderResult
      resultIndex = resultIndex + 1
      failCount = failCount + 1
    ElseIf currentAmount = "" Then
      orderResult = "{" & _
                    """order_no"":""" & JsonEncode(currentOrderNo) & """," & _
                    """phone_no"":""" & JsonEncode(phone_no) & """," & _
                    """result_code"":""0008""," & _
                    """message"":""결제금액누락""" & _
                    "}"
      resultArray(resultIndex) = orderResult
      resultIndex = resultIndex + 1
      failCount = failCount + 1
    ElseIf currentProductDesc = "" Then
      orderResult = "{" & _
                    """order_no"":""" & JsonEncode(currentOrderNo) & """," & _
                    """phone_no"":""" & JsonEncode(phone_no) & """," & _
                    """result_code"":""0007""," & _
                    """message"":""상품명누락""" & _
                    "}"
      resultArray(resultIndex) = orderResult
      resultIndex = resultIndex + 1
      failCount = failCount + 1
    Else
      '// 주문번호 중복 확인
      qry = "SELECT count(order_no) cnt FROM KICC_SHOP_ORDER where terminal_id = '"& terminal_id &"' and order_no = '"& currentOrderNo &"'"
      Set rs = dbCon.Execute(qry)
      mx_cnt = rs("cnt")
      rs.close
      set rs = nothing

      If mx_cnt = 0 Then
        '// 주문 저장 (maxcode는 배치 시작 시 생성된 값 사용)
        Set adoRs = Server.CreateObject("ADODB.Recordset")
        with adoRs
          .Open "KICC_SHOP_ORDER", strConnect, adOpenDynamic, adLockOptimistic
          .AddNew
          .Fields("order_no")      = currentOrderNo
          .Fields("terminal_nm")  = terminal_nm
          .Fields("terminal_id")  = terminal_id
          .Fields("terminal_pw")  = terminal_pw
          .Fields("admin_id")     = admin_id
          .Fields("admin_name")   = admin_name
          .Fields("cust_nm")      = cc_name
          .Fields("good_nm")      = currentProductDesc
          .Fields("cust_email")   = cc_email
          .Fields("amount")       = currentAmount
          .Fields("phone_no")     = phone_no
          .Fields("payment_code") = "0"
          .Fields("request_type") = req_type
        If card_no <> "" Then
          .Fields("RESERVED_4")   = card_no
        End if
        If expire_date <> "" Then
          .Fields("RESERVED_3")   = expire_date
        End if
        If install_month <> "" Then
          .Fields("RESERVED_5")   = install_month
        End if
        If maxcode <> "" Then
          .Fields("auth_no")  = maxcode
        End if
          .Update
        End with
        adoRs.Close
        Set adoRs = nothing

        orderResult = "{" & _
                      """order_no"":""" & JsonEncode(currentOrderNo) & """," & _
                      """phone_no"":""" & JsonEncode(phone_no) & """," & _
                      """result_code"":""0000""," & _
                      """message"":""등록성공""" & _
                      "}"
        resultArray(resultIndex) = orderResult
        resultIndex = resultIndex + 1
        successCount = successCount + 1
      Else
        orderResult = "{" & _
                      """order_no"":""" & JsonEncode(currentOrderNo) & """," & _
                      """phone_no"":""" & JsonEncode(phone_no) & """," & _
                      """result_code"":""0011""," & _
                      """message"":""거래번호중복""" & _
                      "}"
        resultArray(resultIndex) = orderResult
        resultIndex = resultIndex + 1
        failCount = failCount + 1
      End If
    End If
  Next

  '// 데이터베이스 연결 종료
  dbCon.close
  Set dbCon = nothing

  '// ========================================
  '// SMS/MMS 발송 (조건부 실행)
  '// ========================================
  '// 위치: 주문 루프 종료 후 (배치당 1회만 실행)
  '// SMS/KTK 타입일 때만 발송

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
      '// 사용자 정의 메시지가 있으면 앞에 추가
      '// smsMsg = sms_message & " " & cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
      smsMsg = sms_message & ". " 
    Else
      '// 기존 기본 형식
      smsMsg = cc_name & " 님의 주문인증번호는[" & maxcode & "]입니다 "
    End If
    smsMsg = smsMsg & callback_no & " 로전화주십시오"

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
                   """req_result"":" & BuildJsonArray(resultArray) & _
                   "}"

    response.write jsonResponse
    response.end
  End if
%>
