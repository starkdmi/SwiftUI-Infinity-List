# SwiftUI-Infinity-List
SwiftUI incremental loading list view

```
InfinityList(model: self.viewModel) { item in
    Text(item.name)
}
```

# Simple use
```
struct User: InfinityElementSupport {
    var id = UUID()
    var name: String
    
    init(_ name: String) {
        self.name = name
    }
}

struct UserModel: InfinityModelSupport {
    
    public var users: [User] = []
    
    var infintityItems: [User] {
        get { return users }
        set { users = newValue }
    }
}

class UserViewModel: InfinityViewModel<UserModel, User> {
    override func loadMore(completion: @escaping(Response<UserModel>) -> Void) {
        var model = UserModel()
        for index in self.pageIndex * 10 ..< self.pageIndex * 10 + 10 {
            model.users.append(.init("User \(index)"))
        }
        completion(.success(model))
    }
}

struct ContentView: View {
    @ObservedObject var viewModel = UserViewModel()
    var body: some View {
        InfinityList(model: self.viewModel) { item in
            Text(item.name)
        }
    }
}
```

# Advanced use (www.themoviedb.org)
```
struct TheMovieDB: InfinityModelSupport {
    var page: Int
    public var results: [Result]
    var totalPages, totalResults: Int
    
    var infintityItems: [Result] {
        get { return results }
        set { results = newValue }
    }
    
    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

struct Result: InfinityElementSupport {
    var id: Int
    var video: Bool
    var voteCount: Int
    var voteAverage: Double
    var title, releaseDate: String
    var originalLanguage: String
    var originalTitle: String
    var genreIDS: [Int]
    var backdropPath: String
    var adult: Bool
    var overview, posterPath: String
    var popularity: Double?
    var mediaType: String
    
    enum CodingKeys: String, CodingKey {
        case id, video
        case voteCount = "vote_count"
        case voteAverage = "vote_average"
        case title
        case releaseDate = "release_date"
        case originalLanguage = "original_language"
        case originalTitle = "original_title"
        case genreIDS = "genre_ids"
        case backdropPath = "backdrop_path"
        case adult, overview
        case posterPath = "poster_path"
        case popularity
        case mediaType = "media_type"
    }
    
    static func ==(lhs:Result, rhs:Result) -> Bool {
        lhs.id == rhs.id
    }
}

class ItemsViewModel: InfinityViewModel<TheMovieDB, Result> {
    private var cancellableSet: Set<AnyCancellable> = []
    public let decoder: JSONDecoder
    
    dynamic override var items: [Result] {
        get { return super.items }
        set { super.items = newValue }
    }
    
    init() {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        super.init(page: 1)
    }
    
    override func loadMore(completion: @escaping(Response<TheMovieDB>) -> Void) {
        let url = URL(string: "https://api.themoviedb.org/3/trending/movie/week?api_key=\(YOUR_API_KEY)&page=\(pageIndex)")!
        
        URLSession.getUrlJson(url: url, decoder: decoder, completion: completion).store(in: &cancellableSet)
    }
    
    override func shouldLoadMore(_ item: Result) -> Bool {
        if self.items.count >= 4 && item == self.items[self.items.count - 4] {
            return true
        }
        
        return false
    }
}

struct CustomElementView: View {
    let item: Result
    
    var body: some View {
        VStack {
            HStack {
                Text("\(item.id)")
                Text(item.title)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel = ItemsViewModel()
    
    @State var showError = false
    @State var errorMessage = ""
    
    var body: some View {
        InfinityList(model: self.viewModel,
                     onSuccess: { response in
                        print("Page \(response.page) has \(response.infintityItems.count) new items")
        },
                     onError: { error in
                        self.errorMessage = "Error: \(error)"
                        self.showError.toggle()
        }) { item in
            CustomElementView(item: item)
        }
        .alert(isPresented: $showError) {
            Alert(title: Text("Alert"), message: Text(errorMessage), dismissButton: .default(Text("Ok")))
        }
    }
}
```

# Advanced example requirements
I'm using my custom extension for the URLSession task and the simple Response enumeration
```
enum Response<T>: Error {
    case success(T)
    case failure(_ error: Error)
}

extension URLSession {
    static func getUrlJson<T: Decodable>(url: URL, decoder: JSONDecoder, completion loadCompletion: @escaping(Response<T>) -> Void) -> AnyCancellable {
        
        let cancellable: AnyCancellable = self.shared.dataTaskPublisher(for: url)
            .subscribe(on: DispatchQueue.global())
            .retry(3)
            .tryMap() { request -> Data in
                guard let httpResponse = request.response as? HTTPURLResponse,
                    (200...299).contains(httpResponse.statusCode) else {
                        throw URLError(.badServerResponse)
                }
                return request.data
        }
        .decode(type: T.self, decoder: decoder)
        .receive(on: RunLoop.main)
        .sink(receiveCompletion: { completion in
            switch completion {
            case .failure(let error):
                loadCompletion(.failure(error))
            case .finished:
                break
            }
        }) { data in
            loadCompletion(.success(data))
        }
        
        return cancellable
    }
}
```

# And the list UI source code looks like
```
struct InfinityList<Content: View, Model: InfinityModelSupport, Element: InfinityElementSupport>: View {
    
    @ObservedObject var viewModel: InfinityViewModel<Model, Element>
    let itemView: (Element) -> Content
    
    // When new items added
    let onSuccess: ((Model) -> Void)?
    let onError: ((Error) -> Void)?
    
    init<ViewModel: InfinityViewModel<Model, Element>>(model: ViewModel, onSuccess: ((Model) -> Void)? = nil, onError: ((Error) -> Void)? = nil, @ViewBuilder view: @escaping (Element) -> Content) {
        self.viewModel = model
        self.itemView = view
        
        self.onSuccess = onSuccess
        self.onError = onError
    }
    
    var body: some View {
        List(self.viewModel.items, id: \.id) { item in
            self.itemView(item)
                .onAppear {
                    if self.viewModel.shouldLoadMore(item) {
                        self.loadMore()
                    }
            }
        }
        .onAppear(perform: {
            self.loadMore()
        })
    }
    
    public func loadMore() {
        self.viewModel.loadMore { response in
            switch response {
            case let .success(page):
                self.viewModel.items.append(contentsOf: page.infintityItems as! [Element])
                self.viewModel.pageIndex += 1
                
                if self.onSuccess != nil {
                    self.onSuccess!(page)
                }
            case let .failure(error):
                if self.onError != nil {
                    self.onError!(error)
                }
            }
        }
    }
}
```

# InfinityModelSupport, InfinityElementSupport and InfinityViewModel
As you can see the requirements for InfinityList ViewModel is support of InfinityModelSupport, InfinityElementSupport for the items and InfinityViewModel for the Model
```
protocol InfinityModelSupport: Decodable {
    associatedtype T
    var infintityItems: [T] { get set }
}

protocol InfinityElementSupport: Identifiable, Codable, Hashable { }

class InfinityViewModel<Model: Decodable, Element: Equatable>: ObservableObject {
    @Published var items: [Element] = []
    
    public var pageIndex = 0
    
    init(page: Int = 0) {
        self.pageIndex = page
    }
    
    func loadMore(completion: @escaping(Response<Model>) -> Void) {
        
    }
    
    func shouldLoadMore(_ item: Element) -> Bool {
        if let last = self.items.last {
            return last == item
        }
        return false
    }
}
```
