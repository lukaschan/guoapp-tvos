import SwiftUI
import UIKit

/// tvOS 原生搜索界面（UIKit 的 UISearchController + UISearchContainerViewController）：
/// 顶部搜索框与键盘，下方是 SwiftUI 的结果视图，联想词显示在键盘旁。
///
/// 不用 SwiftUI 的 `.searchable`：它会把绑定的文字回写进搜索框，用 iPhone 输入中文时
/// 回写会打断输入法的组字（拼音候选消失、字母重复成「ww」）。这里只读搜索框、从不回写
///（唯一的写入是用户选了联想词）。组字在 iPhone 上进行，电视端只收到上屏的文字。
struct NativeSearchContainer<Results: View>: UIViewControllerRepresentable {
    let model: SearchModel
    let suggestions: [String]
    let prompt: String
    @ViewBuilder let results: () -> Results

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIViewController(context: Context) -> UISearchContainerViewController {
        let resultsController = UIHostingController(rootView: results())
        resultsController.view.backgroundColor = .clear
        let searchController = UISearchController(searchResultsController: resultsController)
        searchController.searchResultsUpdater = context.coordinator
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = prompt
        searchController.searchBar.autocorrectionType = .no
        searchController.searchBar.spellCheckingType = .no
        searchController.searchBar.autocapitalizationType = .none
        context.coordinator.searchController = searchController
        context.coordinator.resultsController = resultsController
        let container = UISearchContainerViewController(searchController: searchController)
        container.view.backgroundColor = UIColor(TVTheme.background)
        return container
    }

    func updateUIViewController(_ container: UISearchContainerViewController, context: Context) {
        context.coordinator.resultsController?.rootView = results()
        context.coordinator.apply(suggestions: suggestions)
    }

    @MainActor
    final class Coordinator: NSObject, UISearchResultsUpdating {
        let model: SearchModel
        weak var searchController: UISearchController?
        var resultsController: UIHostingController<Results>?
        private var appliedSuggestions: [String] = []

        init(model: SearchModel) {
            self.model = model
        }

        func updateSearchResults(for searchController: UISearchController) {
            // 只读，不回写搜索框。
            model.update(text: searchController.searchBar.text ?? "")
        }

        /// 选了键盘旁的联想词：填进搜索框并搜索（这时没有在组字，写入是安全的）。
        func updateSearchResults(for searchController: UISearchController, selecting searchSuggestion: any UISearchSuggestion) {
            let text = searchSuggestion.localizedSuggestion ?? ""
            searchController.searchBar.text = text
            model.update(text: text)
        }

        func apply(suggestions: [String]) {
            guard suggestions != appliedSuggestions, let searchController else { return }
            appliedSuggestions = suggestions
            searchController.searchSuggestions = suggestions.prefix(8).map {
                UISearchSuggestionItem(localizedSuggestion: $0)
            }
        }
    }
}
