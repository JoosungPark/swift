// async_let_sample.swift
// SIL 분석용 샘플 코드

// 1. 기본 async let 사용
func fetchUser() async -> String {
    return "User"
}

func fetchPosts() async -> [String] {
    return ["Post1", "Post2"]
}

func fetchAll() async -> (String, [String]) {
    async let user = fetchUser()
    async let posts = fetchPosts()
    
    return await (user, posts)
}

// 2. for-await 사용
struct Counter: AsyncSequence {
    typealias Element = Int
    let limit: Int
    
    struct AsyncIterator: AsyncIteratorProtocol {
        var current = 0
        let limit: Int
        
        mutating func next() async -> Int? {
            guard current < limit else { return nil }
            current += 1
            return current
        }
    }
    
    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(limit: limit)
    }
}

func processSequence() async {
    for await number in Counter(limit: 5) {
        print(number)
    }
}
