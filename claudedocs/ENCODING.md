# ENCODING.md - 파일 인코딩 가이드

## IIS 서버 환경에서의 ASP 파일 인코딩 요구사항

### 필수 요구사항: UTF-8 with BOM

IIS(Internet Information Services)에서 Classic ASP 파일을 실행할 때는 **반드시 UTF-8 with BOM** 인코딩을 사용해야 합니다.

#### BOM(Byte Order Mark)이란?

- UTF-8 BOM: `EF BB BF` (3바이트)
- 파일 맨 앞에 위치하여 파일이 UTF-8 인코딩임을 명시
- IIS가 파일 인코딩을 올바르게 인식하도록 함

#### 왜 UTF-8 with BOM이 필요한가?

1. **IIS 인코딩 감지 문제**
   - BOM 없이는 IIS가 파일을 잘못된 코드페이지(예: EUC-KR, CP949)로 해석할 수 있음
   - 한글 문자가 깨지거나 '??' 문자로 표시됨

2. **응답 헤더 불일치**
   - ASP 코드에서 `Response.CharSet = "utf-8"`로 설정해도
   - 파일 자체가 다른 인코딩이면 응답 본문이 손상됨

3. **JSON 응답 오류**
   - JSON 응답에 한글이 포함된 경우 클라이언트가 파싱 불가
   - API 호출 실패로 이어짐

## 현재 프로젝트 상황

### ⚠️ 현재 인코딩 상태

```bash
파일: dev/db/kicc_ars_order_v3_batch.asp
현재 인코딩: UTF-8 without BOM
필요 인코딩: UTF-8 with BOM
상태: 수정 필요
```

**검증 명령어:**
```bash
python -c "with open(r'dev\db\kicc_ars_order_v3_batch.asp', 'rb') as f: print('Has BOM:', f.read(3) == b'\xef\xbb\xbf')"
```

### ✅ 올바른 ASP 파일 구조

```asp
<%
  '// BOM이 있는 UTF-8 파일
  '// 파일 첫 바이트: EF BB BF

  '// 응답 인코딩 설정
  Response.CharSet = "utf-8"
  Response.CodePage = 65001
  Response.ContentType = "application/json"

  '// 한글 데이터 처리
  Dim message
  message = "등록성공"  '// BOM 덕분에 정상 처리됨
%>
```

## 인코딩 설정 방법

### 1. Visual Studio Code

**설정:**
1. 파일 열기
2. 하단 상태바에서 현재 인코딩 클릭 (예: "UTF-8")
3. "Reopen with Encoding" 선택
4. "UTF-8 with BOM" 선택
5. **Save with Encoding** → "UTF-8 with BOM" 선택

**settings.json 설정:**
```json
{
  "[asp]": {
    "files.encoding": "utf8bom"
  }
}
```

### 2. Notepad++

1. Encoding 메뉴 → "UTF-8 with BOM" 선택
2. 파일 저장

### 3. Python 스크립트로 변환

```python
# convert_to_utf8_bom.py
import os

def convert_to_utf8_bom(file_path):
    """ASP 파일을 UTF-8 with BOM으로 변환"""
    with open(file_path, 'rb') as f:
        content = f.read()

    # 기존 BOM 제거 (있다면)
    if content.startswith(b'\xef\xbb\xbf'):
        content = content[3:]

    # UTF-8 BOM 추가
    bom = b'\xef\xbb\xbf'
    with open(file_path, 'wb') as f:
        f.write(bom + content)

    print(f"✅ Converted: {file_path}")

# 사용 예시
convert_to_utf8_bom(r'dev\db\kicc_ars_order_v3_batch.asp')
```

### 4. PowerShell 스크립트

```powershell
# convert_to_utf8_bom.ps1
$filePath = "dev\db\kicc_ars_order_v3_batch.asp"
$content = Get-Content -Path $filePath -Raw -Encoding UTF8
$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($filePath, $content, $utf8Bom)
Write-Host "✅ Converted: $filePath"
```

## JSON 요청/응답 처리

### JSON 요청 받기

```asp
<%
  '// UTF-8 with BOM으로 저장된 ASP 파일
  Response.CharSet = "utf-8"
  Response.CodePage = 65001
  Response.ContentType = "application/json"

  '// JSON 바디 읽기 (UTF-8 처리)
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
    objStream.Charset = "utf-8"  '// UTF-8 명시
    ReadRequestBody = objStream.ReadText
    objStream.Close
    Set objStream = Nothing
  End Function

  Dim jsonBody, customerName
  jsonBody = ReadRequestBody()

  '// JSON 파싱 (한글 데이터 포함)
  customerName = ExtractJsonString(jsonBody, "cc_name")  '// "홍길동"
%>
```

### JSON 응답 생성

```asp
<%
  '// UTF-8 with BOM 파일이므로 한글 문자열 정상 처리
  Function JsonEncode(str)
    Dim result
    If IsNull(str) Or str = "" Then
      result = ""
    Else
      result = CStr(str)
      '// 특수문자 이스케이프
      result = Replace(result, "\", "\\")
      result = Replace(result, """", "\""")
      result = Replace(result, vbCrLf, "\n")
    End If
    JsonEncode = result
  End Function

  '// JSON 응답 생성
  Dim jsonResponse, koreanMessage
  koreanMessage = "등록성공"  '// BOM 덕분에 정상 인코딩

  jsonResponse = "{" & _
                 """result_code"":""0000""," & _
                 """message"":""" & JsonEncode(koreanMessage) & """" & _
                 "}"

  Response.Write jsonResponse
  '// 클라이언트가 받는 응답: {"result_code":"0000","message":"등록성공"}
%>
```

## 인코딩 검증 절차

### 1. BOM 확인

**Python:**
```bash
python -c "with open('dev/db/kicc_ars_order_v3_batch.asp', 'rb') as f: bom = f.read(3); print('BOM:', bom.hex(), '✅ OK' if bom == b'\xef\xbb\xbf' else '❌ Missing BOM')"
```

**PowerShell:**
```powershell
$bytes = Get-Content -Path "dev\db\kicc_ars_order_v3_batch.asp" -Encoding Byte -TotalCount 3
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "✅ UTF-8 with BOM"
} else {
    Write-Host "❌ Missing BOM: $($bytes -join ' ')"
}
```

### 2. 응답 테스트

**curl 테스트:**
```bash
curl -X POST https://www.arspg.co.kr/ars/kicc/dev/db/kicc_ars_order_v3_batch.asp \
  -H "Content-Type: application/json" \
  -d '{"mode":"ars_data_add","terminal_id":"05532206","request_type":"ARS","cc_name":"홍길동","phone_no":"01012345678","card_no":"1234567890123456","expire_date":"2512","install_month":"00","orders":[{"order_no":"TEST001","amount":1000,"cc_pord_desc":"테스트상품"}]}' \
  --output - | python -m json.tool
```

**예상 출력 (한글 정상):**
```json
{
  "batch_summary": {
    "total": 1,
    "success": 1,
    "fail": 0
  },
  "req_result": [
    {
      "order_no": "TEST001",
      "phone_no": "01012345678",
      "result_code": "0000",
      "message": "등록성공"
    }
  ]
}
```

### 3. 한글 깨짐 확인

**문제 발생 시 증상:**
```json
{
  "message": "????"  // UTF-8 without BOM
}
```

**정상 응답:**
```json
{
  "message": "등록성공"  // UTF-8 with BOM
}
```

## 배포 체크리스트

### 개발 환경 → 운영 환경

- [ ] ASP 파일이 UTF-8 with BOM 인코딩인지 확인
  ```bash
  python -c "import sys; f=open(sys.argv[1],'rb'); print('✅ OK' if f.read(3)==b'\xef\xbb\xbf' else '❌ No BOM')" dev/db/kicc_ars_order_v3_batch.asp
  ```

- [ ] Response.CharSet = "utf-8" 설정 확인
- [ ] Response.CodePage = 65001 설정 확인
- [ ] JSON 응답 Content-Type 확인: `application/json; charset=utf-8`
- [ ] 한글 테스트 데이터로 API 호출 테스트
- [ ] 응답 JSON이 올바르게 파싱되는지 확인

### 문제 해결

**문제 1: 한글이 '???'로 표시됨**
- **원인**: UTF-8 without BOM
- **해결**: UTF-8 with BOM으로 재저장

**문제 2: JSON 파싱 오류**
- **원인**: 응답 본문 인코딩 불일치
- **해결**: ASP 파일 인코딩과 Response.CharSet 일치 확인

**문제 3: IIS에서만 한글 깨짐 (로컬은 정상)**
- **원인**: IIS 서버의 코드페이지 설정
- **해결**: UTF-8 with BOM 사용 (IIS가 자동 감지)

## 참고 자료

### IIS 및 ASP 인코딩 관련

- **IIS 기본 코드페이지**: 시스템 로케일에 따라 다름 (한국: CP949)
- **UTF-8 BOM의 역할**: IIS가 파일을 UTF-8로 인식하도록 강제
- **Response.CodePage**: 65001 = UTF-8
- **Response.CharSet**: HTTP 응답 헤더의 charset 설정

### UTF-8 BOM 바이트 시퀀스

- **UTF-8 BOM**: `EF BB BF` (3바이트)
- **UTF-16 LE BOM**: `FF FE` (2바이트)
- **UTF-16 BE BOM**: `FE FF` (2바이트)

### Classic ASP 제약사항

- 네이티브 JSON 파싱 미지원 → 정규식 사용
- UTF-8 처리를 위해 ADODB.Stream 필요
- Response.CharSet과 파일 인코딩 일치 필수

## 요약

✅ **필수 규칙:**
1. 모든 ASP 파일은 **UTF-8 with BOM** 인코딩으로 저장
2. `Response.CharSet = "utf-8"` 설정
3. `Response.CodePage = 65001` 설정
4. JSON 바디 읽기 시 `objStream.Charset = "utf-8"` 명시

❌ **금지사항:**
1. UTF-8 without BOM 사용 (IIS 인코딩 감지 실패)
2. EUC-KR, CP949 인코딩 사용 (JSON 응답 깨짐)
3. 파일 인코딩과 Response.CharSet 불일치
