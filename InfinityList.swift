//
//  InfinityList.swift
//  InfinityList
//
//  Created by Starkov Dmitry on 18.05.2020.
//  Copyright © 2020 Starkov Dmitry. All rights reserved.
//

import Foundation
import Combine
import SwiftUI

enum Response<T>: Error {
    case success(T)
    case failure(_ error: Error)
}

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
