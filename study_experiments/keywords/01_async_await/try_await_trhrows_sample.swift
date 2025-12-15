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