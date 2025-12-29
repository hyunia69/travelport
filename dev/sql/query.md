# SQL 쿼리 관리 문서

이 문서는 프로젝트에서 사용하는 SQL 쿼리문을 관리합니다.

---

## SQL 개념 설명

### IDENTITY 컬럼이란?

**IDENTITY 컬럼**은 SQL Server에서 자동으로 증가하는 숫자 값을 생성하는 특수한 컬럼입니다.

#### 기본 개념

```sql
-- IDENTITY 컬럼이 있는 테이블 생성 예시
CREATE TABLE 예제테이블 (
    id INT IDENTITY(1, 1) PRIMARY KEY,  -- IDENTITY 컬럼
    이름 NVARCHAR(50),
    나이 INT
);
```

**IDENTITY(시작값, 증가값)**
- **시작값**: 첫 번째로 생성될 값 (예: 1)
- **증가값**: 각 행마다 증가할 값 (예: 1)

#### 주요 특징

1. **자동 증가**
   - INSERT 시 값을 지정하지 않으면 자동으로 증가하는 숫자가 할당됩니다.
   - 일반적으로 1, 2, 3, 4... 순서로 증가합니다.

2. **고유성 보장**
   - 각 행마다 고유한 값을 가집니다.
   - PRIMARY KEY로 자주 사용됩니다.

3. **수동 입력 제한**
   - 기본적으로 IDENTITY 컬럼에 값을 직접 지정할 수 없습니다.
   - `SET IDENTITY_INSERT 테이블명 ON`을 설정해야 수동 입력이 가능합니다.

#### 사용 예시

```sql
-- 테이블 생성
CREATE TABLE 주문테이블 (
    주문번호 INT IDENTITY(1, 1) PRIMARY KEY,
    고객명 NVARCHAR(50),
    주문금액 INT
);

-- 데이터 삽입 (주문번호는 자동 생성)
INSERT INTO 주문테이블 (고객명, 주문금액)
VALUES ('홍길동', 10000);

-- 결과: 주문번호 = 1 (자동 생성)

INSERT INTO 주문테이블 (고객명, 주문금액)
VALUES ('김철수', 20000);

-- 결과: 주문번호 = 2 (자동 생성)

-- 주문번호를 직접 지정하려고 하면 오류 발생
INSERT INTO 주문테이블 (주문번호, 고객명, 주문금액)
VALUES (999, '이영희', 30000);
-- 오류: IDENTITY_INSERT가 설정되지 않았습니다.
```

#### IDENTITY_INSERT 설정

```sql
-- IDENTITY 컬럼에 수동으로 값 지정하기
SET IDENTITY_INSERT 주문테이블 ON;

INSERT INTO 주문테이블 (주문번호, 고객명, 주문금액)
VALUES (999, '이영희', 30000);
-- 성공: 주문번호 = 999 (수동 지정)

SET IDENTITY_INSERT 주문테이블 OFF;
-- 반드시 OFF로 설정해야 합니다.
```

#### IDENTITY 시드(Seed) 확인 및 재설정

```sql
-- 현재 IDENTITY 값 확인
SELECT IDENT_CURRENT('주문테이블') AS 현재값;

-- 다음에 생성될 IDENTITY 값 확인
SELECT IDENT_CURRENT('주문테이블') + IDENT_INCR('주문테이블') AS 다음값;

-- IDENTITY 시드 재설정 (예: 최대값으로 설정)
DECLARE @maxId INT;
SELECT @maxId = ISNULL(MAX(주문번호), 0) FROM 주문테이블;
DBCC CHECKIDENT('주문테이블', RESEED, @maxId);
```

#### ⚠️ 왜 테이블이 비어있는데도 1부터 시작하지 않을까?

**문제 상황:**
- 테이블에 데이터가 하나도 없는데
- 새로 INSERT하면 1이 아니라 456 같은 숫자부터 시작됨

**원인:**

IDENTITY 컬럼은 **테이블의 데이터 개수**가 아니라 **마지막으로 생성된 IDENTITY 값**을 기억합니다.

**발생 가능한 시나리오:**

1. **이전에 데이터가 있었고 삭제된 경우**
   ```sql
   -- 예시: 이전에 1~455번까지 데이터가 있었음
   INSERT INTO 주문테이블 (고객명, 주문금액) VALUES ('고객1', 1000);  -- 주문번호: 1
   INSERT INTO 주문테이블 (고객명, 주문금액) VALUES ('고객2', 2000);  -- 주문번호: 2
   ...
   INSERT INTO 주문테이블 (고객명, 주문금액) VALUES ('고객455', 1000); -- 주문번호: 455

   -- 모든 데이터 삭제
   DELETE FROM 주문테이블;

   -- 테이블은 비어있지만 IDENTITY는 455를 기억하고 있음
   INSERT INTO 주문테이블 (고객명, 주문금액) VALUES ('새고객', 1000);
   -- 주문번호: 456 (1이 아님!)
   ```

2. **IDENTITY_INSERT로 큰 값을 삽입한 경우**
   ```sql
   SET IDENTITY_INSERT 주문테이블 ON;
   INSERT INTO 주문테이블 (주문번호, 고객명, 주문금액) VALUES (999, '고객', 1000);
   SET IDENTITY_INSERT 주문테이블 OFF;

   -- 이후 삭제
   DELETE FROM 주문테이블;

   -- 다음 INSERT 시
   INSERT INTO 주문테이블 (고객명, 주문금액) VALUES ('새고객', 1000);
   -- 주문번호: 1000 (999 다음 값)
   ```

3. **DBCC CHECKIDENT로 시드를 재설정한 경우**
   ```sql
   -- 시드를 456으로 재설정
   DBCC CHECKIDENT('주문테이블', RESEED, 456);

   -- 다음 INSERT 시
   INSERT INTO 주문테이블 (고객명, 주문금액) VALUES ('새고객', 1000);
   -- 주문번호: 457 (456 다음 값)
   ```

**해결 방법:**

1부터 다시 시작하려면 IDENTITY 시드를 0으로 재설정:

```sql
-- IDENTITY 시드를 0으로 재설정 (다음 값은 1이 됨)
DBCC CHECKIDENT('주문테이블', RESEED, 0);

-- 확인
SELECT IDENT_CURRENT('주문테이블') AS 현재시드값;  -- 0

-- 다음 INSERT
INSERT INTO 주문테이블 (고객명, 주문금액) VALUES ('새고객', 1000);
-- 주문번호: 1 (정상적으로 1부터 시작)
```

**주의사항:**
- ⚠️ **TRUNCATE TABLE을 사용하면 IDENTITY가 1로 초기화됩니다.**
- ⚠️ **DELETE는 데이터만 삭제하고 IDENTITY 값은 유지합니다.**
- ⚠️ **시드를 재설정할 때는 기존 데이터와 충돌하지 않도록 주의하세요.**

**TRUNCATE vs DELETE 비교:**

```sql
-- DELETE 사용 (IDENTITY 유지)
DELETE FROM 주문테이블;
INSERT INTO 주문테이블 (고객명, 주문금액) VALUES ('고객', 1000);
-- 주문번호: 이전 최대값 + 1

-- TRUNCATE 사용 (IDENTITY 초기화)
TRUNCATE TABLE 주문테이블;
INSERT INTO 주문테이블 (고객명, 주문금액) VALUES ('고객', 1000);
-- 주문번호: 1 (초기화됨)
```

#### 실제 사용 사례

**장점:**
- ✅ **고유한 ID 자동 생성**: 각 레코드에 고유한 번호를 자동으로 부여
- ✅ **간편함**: INSERT 시 ID 값을 신경 쓸 필요 없음
- ✅ **일관성**: 중복이나 누락 없이 순차적으로 번호 부여

**단점:**
- ❌ **수동 제어 어려움**: 특정 값을 지정하려면 IDENTITY_INSERT 설정 필요
- ❌ **삭제 후 공백**: 데이터 삭제 후에도 IDENTITY 값은 계속 증가 (1, 2, 3 삭제 후 다음 값은 4)
- ❌ **복사 시 주의**: 다른 서버로 데이터 복사 시 IDENTITY 값 충돌 가능

**일반적인 용도:**
- 기본키(Primary Key)로 사용
- 주문번호, 회원번호, 게시글 번호 등 순차적 번호가 필요한 경우
- 외래키(Foreign Key) 참조의 기준점

---

## KICC_SHOP_ORDER 테이블

### 모든 데이터 삭제

#### DELETE 문 사용
```sql
DELETE FROM KICC_SHOP_ORDER;
```

**설명:**
- `KICC_SHOP_ORDER` 테이블의 모든 행을 삭제합니다.
- 행 단위로 삭제하므로 트랜잭션 로그가 기록됩니다.
- IDENTITY 컬럼이 있는 경우 값이 초기화되지 않습니다.
- `WHERE` 절을 추가하여 조건부 삭제가 가능합니다.

**주의사항:**
- ⚠️ **데이터 삭제는 되돌릴 수 없습니다. 실행 전 반드시 백업을 수행하세요.**
- 프로덕션 환경에서 실행 시 신중하게 검토하세요.
- 삭제된 행 수를 확인하려면 실행 후 `@@ROWCOUNT`를 확인할 수 있습니다.

#### TRUNCATE 문 사용 (대안)
```sql
TRUNCATE TABLE KICC_SHOP_ORDER;
```

**설명:**
- `DELETE`보다 빠르게 모든 데이터를 삭제합니다.
- 트랜잭션 로그를 최소한으로 기록합니다.
- IDENTITY 컬럼이 있는 경우 값이 초기화됩니다.
- 외래키 제약조건이 있는 경우 사용할 수 없습니다.

**주의사항:**
- ⚠️ **데이터 삭제는 되돌릴 수 없습니다. 실행 전 반드시 백업을 수행하세요.**
- 외래키 참조가 있는 경우 `DELETE` 문을 사용해야 합니다.

---

## 사용 예시

### 조건부 삭제
특정 조건에 맞는 데이터만 삭제하려면 `WHERE` 절을 사용합니다:

```sql
-- 특정 터미널 ID의 주문만 삭제
DELETE FROM KICC_SHOP_ORDER
WHERE terminal_id = 'TERM001';

-- 특정 날짜 이전의 주문 삭제
DELETE FROM KICC_SHOP_ORDER
WHERE reg_date < '2024-01-01';
```

---

## KICC_SHOP_ADMIN 테이블

### 서버 간 데이터 복사

#### 서버 정보
- **소스 서버**: 211.196.157.119 (arspg_web 데이터베이스)
- **대상 서버**: 211.196.157.121 (데이터베이스 확인 필요)

#### 방법 1: OPENROWSET 사용 (권장)

대상 서버(211.196.157.121)에서 실행:

```sql
-- 1단계: 기존 데이터 삭제 (선택사항)
DELETE FROM KICC_SHOP_ADMIN;

-- 2단계: 소스 서버에서 데이터 복사
INSERT INTO KICC_SHOP_ADMIN
SELECT * FROM OPENROWSET(
    'SQLNCLI',
    'Server=211.196.157.119;Database=arspg_web;UID=sa;PWD=medi@ford;',
    'SELECT * FROM KICC_SHOP_ADMIN'
);
```

**설명:**
- `OPENROWSET`을 사용하여 원격 서버의 데이터를 직접 조회하고 삽입합니다.
- 대상 서버에서 실행하는 쿼리입니다.
- SQL Server에서 `Ad Hoc Distributed Queries` 옵션이 활성화되어 있어야 합니다.

**사전 설정 (필요한 경우):**
```sql
-- Ad Hoc Distributed Queries 활성화
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Ad Hoc Distributed Queries', 1;
RECONFIGURE;
```

#### 방법 2: Linked Server 사용

**1단계: Linked Server 생성 (대상 서버에서 실행)**

```sql
-- Linked Server 생성
EXEC sp_addlinkedserver
    @server = 'SOURCE_SERVER',
    @srvproduct = 'SQL Server';

EXEC sp_addlinkedsrvlogin
    @rmtsrvname = 'SOURCE_SERVER',
    @useself = 'false',
    @locallogin = NULL,
    @rmtuser = 'sa',
    @rmtpassword = 'medi@ford';
```

**2단계: 데이터 복사**

```sql
-- 기존 데이터 삭제 (선택사항)
DELETE FROM KICC_SHOP_ADMIN;

-- 데이터 복사
INSERT INTO KICC_SHOP_ADMIN
SELECT * FROM SOURCE_SERVER.arspg_web.dbo.KICC_SHOP_ADMIN;
```

**3단계: Linked Server 삭제 (선택사항)**

```sql
EXEC sp_dropserver 'SOURCE_SERVER', 'droplogins';
```

#### 방법 3: BCP (Bulk Copy Program) 사용

**1단계: 소스 서버에서 데이터 내보내기**

```cmd
bcp "arspg_web.dbo.KICC_SHOP_ADMIN" out "C:\temp\KICC_SHOP_ADMIN.dat" -S 211.196.157.119 -U sa -P "medi@ford" -c -T
```

**2단계: 대상 서버로 데이터 가져오기**

```cmd
bcp "데이터베이스명.dbo.KICC_SHOP_ADMIN" in "C:\temp\KICC_SHOP_ADMIN.dat" -S 211.196.157.121 -U 사용자명 -P "비밀번호" -c -T
```

#### 방법 4: 조건부 복사 (WHERE 절 사용)

특정 조건에 맞는 데이터만 복사:

```sql
-- OPENROWSET 사용 예시
INSERT INTO KICC_SHOP_ADMIN
SELECT * FROM OPENROWSET(
    'SQLNCLI',
    'Server=211.196.157.119;Database=arspg_web;UID=sa;PWD=medi@ford;',
    'SELECT * FROM KICC_SHOP_ADMIN WHERE reg_date >= ''2024-01-01'''
);
```

#### 방법 5: 컬럼 지정 복사

특정 컬럼만 복사하거나 순서가 다른 경우:

```sql
INSERT INTO KICC_SHOP_ADMIN (컬럼1, 컬럼2, 컬럼3, ...)
SELECT 컬럼1, 컬럼2, 컬럼3, ...
FROM OPENROWSET(
    'SQLNCLI',
    'Server=211.196.157.119;Database=arspg_web;UID=sa;PWD=medi@ford;',
    'SELECT 컬럼1, 컬럼2, 컬럼3, ... FROM KICC_SHOP_ADMIN'
);
```

**주의사항:**
- ⚠️ **데이터 복사 전 대상 테이블의 기존 데이터를 확인하고 필요시 백업하세요.**
- 대상 테이블의 스키마가 소스 테이블과 동일한지 확인하세요.
- IDENTITY 컬럼이 있는 경우 복사 방법을 선택해야 합니다 (아래 참조).
- 네트워크 연결 상태를 확인하세요.
- 대용량 데이터의 경우 배치 단위로 나누어 복사하는 것을 고려하세요.

#### IDENTITY 컬럼이 있는 경우의 복사 방법

**IDENTITY_INSERT가 OFF인 경우:**
- ❌ **IDENTITY 컬럼에 값을 직접 지정할 수 없습니다.**
- ✅ **IDENTITY 컬럼을 제외하고 복사하면 자동으로 새 값이 생성됩니다.**
- ✅ **IDENTITY 값을 그대로 복사하려면 IDENTITY_INSERT를 ON으로 설정해야 합니다.**

**방법 A: IDENTITY 값을 새로 생성 (IDENTITY_INSERT OFF 상태)**

IDENTITY 컬럼을 제외하고 복사하면 SQL Server가 자동으로 새 IDENTITY 값을 생성합니다:

```sql
-- IDENTITY 컬럼(id)을 제외하고 복사
INSERT INTO KICC_SHOP_ADMIN (컬럼1, 컬럼2, 컬럼3, ...)
SELECT 컬럼1, 컬럼2, 컬럼3, ...
FROM OPENROWSET(
    'SQLNCLI',
    'Server=211.196.157.119;Database=arspg_web;UID=sa;PWD=medi@ford;',
    'SELECT 컬럼1, 컬럼2, 컬럼3, ... FROM KICC_SHOP_ADMIN'
);
```

**장점:**
- 간단하고 안전합니다.
- IDENTITY 값 충돌이 발생하지 않습니다.

**단점:**
- 원본 IDENTITY 값이 유지되지 않습니다.
- 다른 테이블과의 관계가 IDENTITY 값에 의존하는 경우 문제가 될 수 있습니다.

**방법 B: IDENTITY 값을 그대로 복사 (IDENTITY_INSERT ON 설정)**

원본 IDENTITY 값을 그대로 복사하려면 `SET IDENTITY_INSERT`를 사용합니다:

```sql
-- 1단계: IDENTITY_INSERT 활성화
SET IDENTITY_INSERT KICC_SHOP_ADMIN ON;

-- 2단계: IDENTITY 컬럼을 포함하여 복사
INSERT INTO KICC_SHOP_ADMIN (id, 컬럼1, 컬럼2, 컬럼3, ...)
SELECT id, 컬럼1, 컬럼2, 컬럼3, ...
FROM OPENROWSET(
    'SQLNCLI',
    'Server=211.196.157.119;Database=arspg_web;UID=sa;PWD=medi@ford;',
    'SELECT id, 컬럼1, 컬럼2, 컬럼3, ... FROM KICC_SHOP_ADMIN'
);

-- 3단계: IDENTITY_INSERT 비활성화 (반드시 실행)
SET IDENTITY_INSERT KICC_SHOP_ADMIN OFF;
```

**주의사항:**
- ⚠️ **IDENTITY_INSERT는 세션당 하나의 테이블에만 설정할 수 있습니다.**
- ⚠️ **반드시 `SET IDENTITY_INSERT ... OFF`를 실행해야 합니다.**
- ⚠️ **IDENTITY 값이 중복되면 오류가 발생합니다.**
- ⚠️ **복사 후 IDENTITY 시드 값을 업데이트해야 할 수 있습니다.**

**방법 C: IDENTITY 시드 값 업데이트 (방법 B 사용 후)**

IDENTITY 값을 복사한 후, 다음 IDENTITY 값이 올바르게 설정되도록 시드를 업데이트합니다:

```sql
-- 현재 테이블의 최대 IDENTITY 값 확인
DECLARE @maxId INT;
SELECT @maxId = ISNULL(MAX(id), 0) FROM KICC_SHOP_ADMIN;

-- IDENTITY 시드 값 재설정
DBCC CHECKIDENT('KICC_SHOP_ADMIN', RESEED, @maxId);
```

**실제 사용 예시 (KICC_SHOP_ADMIN 테이블):**

```sql
-- 예시 1: IDENTITY 값 새로 생성 (간단한 방법)
INSERT INTO KICC_SHOP_ADMIN (admin_id, admin_name, terminal_id, ...)
SELECT admin_id, admin_name, terminal_id, ...
FROM OPENROWSET(
    'SQLNCLI',
    'Server=211.196.157.119;Database=arspg_web;UID=sa;PWD=medi@ford;',
    'SELECT admin_id, admin_name, terminal_id, ... FROM KICC_SHOP_ADMIN'
);

-- 예시 2: IDENTITY 값 그대로 복사 (원본 값 유지 필요 시)
SET IDENTITY_INSERT KICC_SHOP_ADMIN ON;

INSERT INTO KICC_SHOP_ADMIN (id, admin_id, admin_name, terminal_id, ...)
SELECT id, admin_id, admin_name, terminal_id, ...
FROM OPENROWSET(
    'SQLNCLI',
    'Server=211.196.157.119;Database=arspg_web;UID=sa;PWD=medi@ford;',
    'SELECT id, admin_id, admin_name, terminal_id, ... FROM KICC_SHOP_ADMIN'
);

SET IDENTITY_INSERT KICC_SHOP_ADMIN OFF;

-- IDENTITY 시드 업데이트
DECLARE @maxId INT;
SELECT @maxId = ISNULL(MAX(id), 0) FROM KICC_SHOP_ADMIN;
DBCC CHECKIDENT('KICC_SHOP_ADMIN', RESEED, @maxId);
```

---

## 참고사항

- 모든 쿼리는 테스트 환경에서 먼저 검증한 후 프로덕션에 적용하세요.
- 중요한 데이터를 다루는 쿼리는 반드시 백업 후 실행하세요.
- 쿼리 실행 전 실행 계획을 확인하여 성능에 미치는 영향을 검토하세요.

