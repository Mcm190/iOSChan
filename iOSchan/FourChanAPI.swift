import Foundation

class FourChanAPI {
    static let shared = FourChanAPI()
    
    init() {}
    
    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData // <--- THE FIX
        request.timeoutInterval = 30
        return request
    }
    
    func fetchBoards(completion: @escaping (Result<[Board], Error>) -> Void) {
        guard let url = URL(string: "https://a.4cdn.org/boards.json") else { return }
        
        let request = makeRequest(url: url)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(BoardListResponse.self, from: data)
                completion(.success(response.boards))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func fetchThreads(boardID: String, completion: @escaping (Result<[Thread], Error>) -> Void) {
        guard let url = URL(string: "https://a.4cdn.org/\(boardID)/catalog.json") else { return }
        
        let request = makeRequest(url: url)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { return }
            
            do {
                let pages = try JSONDecoder().decode([CatalogPage].self, from: data)
                let allThreads = pages.flatMap { $0.threads }
                completion(.success(allThreads))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func fetchThreadDetails(board: String, threadNo: Int, completion: @escaping (Result<[Thread], Error>) -> Void) {
        guard let url = URL(string: "https://a.4cdn.org/\(board)/thread/\(threadNo).json") else { return }
        
        let request = makeRequest(url: url)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse else { completion(.failure(NSError(domain: "API", code: -1))); return }

            if http.statusCode == 404 {
                completion(.failure(APIError.notFound))
                return
            }

            guard let data = data else { completion(.failure(APIError.noData)); return }
            
            do {
                let response = try JSONDecoder().decode(ThreadDetailResponse.self, from: data)
                completion(.success(response.posts))
            } catch {
                completion(.failure(APIError.decodingError(error)))
            }
        }.resume()
    }

    func fetchArchivedThreads(boardID: String, limit: Int = 50, completion: @escaping (Result<[Thread], Error>) -> Void) {
        guard let url = URL(string: "https://a.4cdn.org/\(boardID)/archive.json") else { return }

        let request = makeRequest(url: url)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(APIError.noData)); return }

            do {
                let ids = try JSONDecoder().decode([Int].self, from: data)
                let limited = Array(ids.prefix(limit))

                var results: [Thread] = []
                let group = DispatchGroup()
                let lock = NSLock()
                var lastError: Error?

                for id in limited {
                    group.enter()
                    self.fetchThreadDetails(board: boardID, threadNo: id) { res in
                        switch res {
                        case .success(let posts):
                            if let op = posts.first {
                                lock.lock()
                                results.append(op)
                                lock.unlock()
                            }
                        case .failure(let err):
                            lastError = err
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .global()) {
                    if results.isEmpty, let err = lastError {
                        completion(.failure(err))
                    } else {
                        let sorted = results.sorted(by: { $0.time > $1.time })
                        completion(.success(sorted))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

enum APIError: Error {
    case notFound
    case noData
    case decodingError(Error)
}
