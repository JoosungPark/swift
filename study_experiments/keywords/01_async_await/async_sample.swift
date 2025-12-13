func fetchData() async -> Int {
    return 42
}

func processData() async {
    print("Start")
    let data = await fetchData()
    print("End: \(data)")
}