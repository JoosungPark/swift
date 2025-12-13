# Try await / throw + async

발표자: Charlie Choi
작성일: 2025년 12월 9일
주제: Try await / throws + async

## 🎯 Core Concept: "중단점은 곧 실패 가능 지점이다"

(Suspension Point as a Failure Point)

`try await`의 핵심은 "잠깐 멈췄다(await) 다시 시작할 때, 세상이 망해있을 수도 있다(try)"는 것을 받아들이는 것입니다.

- `await`: "나 잠깐 멈출게." (Suspend)
- `try`: "다시 눈떴을 때 에러가 있거나, 취소됐으면 처리할게." (Handle Failure)

이 두 가지가 합쳐져서 "비동기 에러 핸들링"이라는 강력한 흐름을 만듭니다.

---

## 🔎 A. 언어 스펙 (Language Spec)

### 1. 정의 (Definition)

- `async`: 함수가 실행 도중 일시 중단(Suspend)될 수 있음을 나타내는 함수 타입 수식어입니다.
- `throws`: 함수가 값을 반환하지 않고 에러를 전파(Propagate)하며 종료될 수 있음을 나타냅니다.
- `try await`: 호출 지점(Call Site)에서 "여기서 중단될 수 있고(await), 실패할 수 있음(try)"을 명시적으로 표시하는 문법입니다.

### 2. 사용 예시 (Usage)

```swift
// 정의: 비동기적으로 실행되며 에러를 던질 수 있음
func fetchData() async throws -> String {
    try await Task.sleep(nanoseconds: 1_000_000)
    return "Success"
}

func process() async {
    do {
        // 호출: 기다리고(await), 에러를 잡을 준비(try)를 함
        let data = try await fetchData()
        print(data)
    } catch {
        print("Error: \(error)")
    }
}
```

### 3. 컴파일 타임 보장 (Compile-time Guarantees)

Swift 컴파일러는 동시성 코드가 안전하게 실행되도록 다음 사항들을 강제합니다.

- 비동기 컨텍스트 강제 (Async Context Enforcement): `async` 함수는 반드시 비동기 컨텍스트(`Task`, 다른 `async` 함수) 내부에서만 호출되어야 합니다.
- 에러 처리 강제 (Error Handling Enforcement): `throws`가 붙은 함수는 반드시 `try` 키워드와 함께 호출되어야 하며, `do-catch` 등으로 에러를 처리하거나 다시 던져야(`throws`) 합니다.
- 격리 보장 (Isolation Guarantee): Actor 격리 함수(`@MainActor` 등)를 호출할 때는 반드시 `await`를 사용하여 컨텍스트 스위칭(Hop)을 허용해야 합니다.

### 4. 오용 시 컴파일 에러 케이스 (Misuse Cases)

### Case 1: 동기 함수에서 비동기 함수 호출

```swift
func syncFunction() {
    // ❌ Error: 'async' call in a function that does not support concurrency
    let data = await fetchData()
}
```

- 이유: 동기 함수는 "멈출(Suspend)" 능력이 없기 때문입니다. `Task { ... }`로 감싸야 합니다.

### Case 2: 에러 처리 누락

```swift
func asyncFunction() async {
    // ❌ Error: Call can throw but is not marked with 'try'
    let data = await fetchData()
}
```

- 이유: 에러가 발생했을 때 프로그램이 어떻게 행동해야 할지 정의되지 않았기 때문입니다. `try await` 혹은 `try? await`를 써야 합니다.

### Case 3: Actor 격리 위반

```swift
func normalFunction() {
    // ❌ Error: Call to main actor-isolated global function 'updateUI' in a synchronous nonisolated context
    updateUI()
}
```

- 이유: 메인 스레드로 점프(Hop)해야 하는데, 동기 함수는 점프할 수 없기 때문입니다.

---

## 🔎 B. SIL 관찰 (SIL Observation)

`swiftc -emit-sil` 명령어로 확인한 내부 동작입니다.

### 1. 변환된 함수 시그니처

```
// @async: 비동기 함수임
// @error: 에러를 별도의 리턴 채널로 반환함
sil hidden @...fetchData... : $@convention(thin) @async () -> (@owned String, @error any Error)
```

### 2. 상태 머신 번호 (State Machine Blocks)

`try await` 호출은 `try_apply` 명령어로 변환되어, 코드 흐름을 물리적으로 분리합니다.

```
// bb0: 호출 전 (Before Call)
try_apply %1() : ... , normal bb1, error bb3

// --- 여기서 코드가 끊어짐 (Suspension Point) ---

// bb1: 성공 시 재개 지점 (Resume Success)
bb1(%success : $String):
  // ...

// bb3: 실패 시 재개 지점 (Resume Error)
bb3(%error : $Error):
  // ...
```

### 3. Continuation 저장 위치

- 함수가 중단(Suspend)되면, 현재 함수의 로컬 변수와 상태는 힙(Heap)에 할당된 `AsyncContext`라는 객체에 저장됩니다.

```
%4 = call swiftcc ptr @swift_task_alloc(i64 %3) #2
```

- 이것이 동기 함수(스택 사용)와 가장 큰 차이점입니다.

### 4. Suspend/Resume 포인트

- `try_apply` 명령어가 실행되는 순간이 Suspend Point입니다.
- 작업이 완료되면 런타임이 `bb1` 혹은 `bb3` 블록으로 점프하여 실행을 Resume합니다.

---

## 🔎 C. Swift 오픈소스 구현 (Swift Open Source Implementation)

### 1. 담당 파일

- SIL 생성: `lib/SILGen/SILGenApply.cpp` (`emitApply` 함수에서 `try_apply` 생성)
- 런타임 (Task 관리): `stdlib/public/Concurrency/Task.cpp` (`swift_task_switch` 함수에서 컨텍스트 전환 처리)

### 2. 핵심 타입/함수

- `AsyncContext`: 비동기 함수의 스택 프레임 역할을 하는 힙 객체. 함수의 지역 변수들이 여기 저장됩니다.
- `TaskFuture`: 비동기 작업의 결과를 저장하고 대기자(Waiter)를 관리하는 구조체.
- `swift_task_alloc`: 비동기 함수 호출 시 `AsyncContext`를 힙에 할당하는 런타임 함수.

### 3. 호출 흐름 (Call Flow)

1. Caller가 `swift_task_alloc`으로 `AsyncContext` 생성
2. Callee(`async` 함수) 호출
3. Callee가 중단 필요 시 `swift_task_switch` 호출하여 제어권 반환
4. 작업 완료 후 `swift_task_resume`으로 Caller의 `AsyncContext` 복원 및 재개

---

## 🔎 D. 런타임 동작 (Runtime Behavior)

### 1. 실제 실행 시 작업

- Allocation: `async` 함수 호출 시 스택 대신 힙에 프레임(Async Frame)을 할당합니다.
- Context Switch: `hop_to_executor` 명령어를 통해 현재 스레드와 목표 Executor를 비교하고, 필요시 스레드를 변경합니다.

### 2. 비용 (Cost Model)

- 함수 호출: 동기 함수보다 오버헤드가 있습니다 (힙 할당 + ARC 발생).
- Suspend/Resume: 시스템 스레드를 블로킹(Blocking)하는 것보다는 훨씬 저렴합니다. 스레드는 멈추지 않고 다른 일을 하러 갑니다.

### 3. 안전성 (Safety) 보장 방식

- Cooperative Thread Pool: 런타임은 코어 수에 맞는 고정된 스레드 풀을 운영하여, 과도한 컨텍스트 스위칭(Thread Explosion)을 방지합니다.
- Data Race 방지: `hop_to_executor`를 통해, 특정 데이터(Actor)에는 한 번에 하나의 스레드만 접근하도록 강제합니다.

---

## ⚖️ 비교 분석: async vs async throws

가장 중요한 차이는 "돌아오는 길(Resume Path)이 하나인가, 두 개인가"입니다.

### 1. `async` (Non-throwing)

- 의미: "멈출 순 있지만, 반드시 성공해서 돌아온다."
- SIL 명령어: `apply`
- 흐름: 외길 인생. 중단되었다가 깨어나면 무조건 다음 줄을 실행합니다.

### 2. `async throws` (Throwing)

- 의미: "멈출 수 있고, 돌아올 때 성공(Normal)할 수도, 실패(Error)할 수도 있다."
- SIL 명령어: `try_apply`
- 흐름: 갈림길. 중단되었다가 깨어나는 순간, 인생이 두 갈래로 나뉩니다.

---

## 💡 결론 (Summary)

`try await`를 쓴다는 것은 단순히 문법을 맞추는 게 아니라, "내 코드가 언제든 멈출 수 있고, 멈춘 사이에 무슨 일이든(에러, 취소) 일어날 수 있음"을 방어하겠다는 선언입니다.
