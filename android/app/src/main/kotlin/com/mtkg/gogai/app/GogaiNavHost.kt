package com.mtkg.gogai.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import androidx.window.core.layout.WindowWidthSizeClass
import com.mtkg.gogai.di.AppContainer
import com.mtkg.gogai.store.StockStore
import com.mtkg.gogai.ui.articles.ArticleDetailScreen
import com.mtkg.gogai.ui.articles.ArticleListScreen
import com.mtkg.gogai.ui.onboarding.ServerSetupScreen
import com.mtkg.gogai.ui.settings.AdminScreen
import com.mtkg.gogai.ui.settings.SettingsScreen
import com.mtkg.gogai.ui.sidebar.SidebarScreen
import com.mtkg.gogai.ui.stocks.StockCategoryListScreen
import com.mtkg.gogai.ui.stocks.StockDetailScreen
import com.mtkg.gogai.ui.stocks.StockListScreen
import kotlin.time.Duration.Companion.minutes
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable

@Serializable
private object SidebarRoute

@Serializable
private data class ArticleListRoute(val feedId: Int? = null, val groupId: Int? = null)

@Serializable
private data class ArticleDetailRoute(val articleId: Int)

@Serializable
private object StockCategoryListRoute

@Serializable
private data class StockListRoute(val categoryId: Int, val categoryName: String)

@Serializable
private data class StockDetailRoute(val stockId: Int)

@Serializable
private object SettingsRoute

@Serializable
private object AdminRoute

/// アプリのルート。サーバー未設定なら ServerSetupScreen、設定済みならメイン UI を出し分ける。
/// resolvedUrl の購読・自動更新（起動時/復帰時/5分ごと）もここで駆動する
/// （iOS GogaiApp の onChange/.task 群に相当）。
@Composable
fun GogaiRoot(container: AppContainer) {
    val serverUrl by container.serverUrlManager.serverUrl.collectAsState()
    val resolvedUrl by container.serverUrlManager.resolvedUrl.collectAsState()
    val lifecycleOwner = LocalLifecycleOwner.current

    // iOS: .task { resolve() } + .onChange(of: serverURL) { resolve() } 相当。
    // Compose の LaunchedEffect(key) は初回コンポーズでも必ず一度実行されるため、
    // 起動時の解決と「後から serverURL が変わった場合の再解決」の両方を1つでまかなえる。
    LaunchedEffect(serverUrl) {
        if (serverUrl != null) container.serverUrlManager.resolve()
    }

    // iOS: .onChange(of: resolvedURL, initial: true) { configureStores() } 相当。
    LaunchedEffect(resolvedUrl) {
        val url = resolvedUrl ?: return@LaunchedEffect
        container.configureStores(url)
    }

    // iOS: バックグラウンド復帰時の articleStore.refresh() + 5分ごとの自動更新タスク相当。
    // repeatOnLifecycle(RESUMED) の初回突入では configureStores() 側の初回フェッチと
    // 重複させないため hasEnteredResumed フラグで抑制する（iOS の hasLaunched 相当）。
    LaunchedEffect(resolvedUrl, lifecycleOwner) {
        if (resolvedUrl == null) return@LaunchedEffect
        var hasEnteredResumed = false
        lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            if (hasEnteredResumed) {
                container.articleStore.refresh()
            }
            hasEnteredResumed = true
            while (true) {
                delay(5.minutes)
                container.articleStore.refresh()
            }
        }
    }

    if (serverUrl == null) {
        ServerSetupScreen(serverUrlManager = container.serverUrlManager, httpClient = container.httpClient)
    } else {
        GogaiMainUi(container)
    }
}

@Composable
private fun GogaiMainUi(container: AppContainer) {
    val widthSizeClass = currentWindowAdaptiveInfo().windowSizeClass.windowWidthSizeClass
    if (widthSizeClass == WindowWidthSizeClass.EXPANDED) {
        ExpandedLayout(container)
    } else {
        CompactNavHost(container)
    }
}

/// iPhone 相当（Compact）: NavHost バックスタックで Sidebar → ArticleList → ArticleDetail、
/// および Sidebar/ArticleList → StockCategoryList → StockList → StockDetail を push する
/// （iOS は記事とストックを同一 NavigationStack で管理しているのに合わせ、1つの NavHost にまとめる）。
@Composable
private fun CompactNavHost(container: AppContainer) {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = SidebarRoute) {
        composable<SidebarRoute> {
            SidebarScreen(
                groupStore = container.groupStore,
                feedStore = container.feedStore,
                articleStore = container.articleStore,
                settingsStore = container.settingsStore,
                onSelectAll = { navController.navigate(ArticleListRoute()) },
                onSelectFeed = { feedId -> navController.navigate(ArticleListRoute(feedId = feedId)) },
                onSelectGroup = { groupId -> navController.navigate(ArticleListRoute(groupId = groupId)) },
                onStockTap = { navController.navigate(StockCategoryListRoute) },
                onSettingsTap = { navController.navigate(SettingsRoute) },
            )
        }
        composable<ArticleListRoute> { backStackEntry ->
            val route = backStackEntry.toRoute<ArticleListRoute>()
            ArticleListScreen(
                feedId = route.feedId,
                groupId = route.groupId,
                articleStore = container.articleStore,
                feedStore = container.feedStore,
                groupStore = container.groupStore,
                stockStore = container.stockStore,
                onArticleSelected = { articleId -> navController.navigate(ArticleDetailRoute(articleId)) },
                onStockTap = { navController.navigate(StockCategoryListRoute) },
            )
        }
        composable<ArticleDetailRoute> { backStackEntry ->
            val route = backStackEntry.toRoute<ArticleDetailRoute>()
            ArticleDetailScreen(articleId = route.articleId, articleStore = container.articleStore)
        }
        stockGraph(navController, container.stockStore)
        settingsGraph(navController, container, onClose = { navController.popBackStack() })
    }
}

/// SettingsScreen → AdminScreen の遷移（iOS: SettingsView 内の NavigationLink { AdminView() } 相当）。
/// CompactNavHost・SettingsOverlayNavHost の両方から呼べるよう NavGraphBuilder の拡張にしている。
private fun NavGraphBuilder.settingsGraph(navController: NavHostController, container: AppContainer, onClose: () -> Unit) {
    composable<SettingsRoute> {
        SettingsScreen(
            settingsStore = container.settingsStore,
            serverUrlManager = container.serverUrlManager,
            keyValueStore = container.keyValueStore,
            secretStore = container.secretStore,
            appCache = container.appCache,
            onClose = onClose,
            onNavigateAdmin = { navController.navigate(AdminRoute) },
        )
    }
    composable<AdminRoute> {
        AdminScreen(
            settingsStore = container.settingsStore,
            serverUrlManager = container.serverUrlManager,
            groupStore = container.groupStore,
            feedStore = container.feedStore,
            articleStore = container.articleStore,
            onBack = { navController.popBackStack() },
        )
    }
}

/// StockCategoryList → StockList → StockDetail の3段の遷移（iOS stockDestinations() 相当）。
/// CompactNavHost・StockOverlayNavHost の両方から呼べるよう NavGraphBuilder の拡張にしている。
private fun NavGraphBuilder.stockGraph(navController: NavHostController, stockStore: StockStore, onClose: (() -> Unit)? = null) {
    composable<StockCategoryListRoute> {
        val aiAvailable = stockStore.summarizer != null
        StockCategoryListScreen(
            stockStore = stockStore,
            onCategorySelected = { categoryId ->
                val name = stockStore.categories.value.firstOrNull { it.id == categoryId }?.name.orEmpty()
                navController.navigate(StockListRoute(categoryId = categoryId, categoryName = name))
            },
            onClose = onClose,
            aiAvailable = aiAvailable,
        )
    }
    composable<StockListRoute> { backStackEntry ->
        val route = backStackEntry.toRoute<StockListRoute>()
        val aiAvailable = stockStore.summarizer != null
        StockListScreen(
            categoryId = route.categoryId,
            categoryName = route.categoryName,
            stockStore = stockStore,
            onStockSelected = { stockId -> navController.navigate(StockDetailRoute(stockId)) },
            aiAvailable = aiAvailable,
        )
    }
    composable<StockDetailRoute> { backStackEntry ->
        val route = backStackEntry.toRoute<StockDetailRoute>()
        val aiAvailable = stockStore.summarizer != null
        StockDetailScreen(
            stockId = route.stockId,
            stockStore = stockStore,
            onDeleted = { navController.popBackStack() },
            aiAvailable = aiAvailable,
        )
    }
}

/// タブレット相当（Expanded）: Sidebar | ArticleList | ArticleDetail を Row で並べる自作 3 ペイン。
/// material3-adaptive の ListDetailPaneScaffold は 3 ペイン構成に素直に合わないため使わない。
/// ストックは iOS の fullScreenCover 相当として、3 ペインの上に専用 NavHost を全画面表示する。
@Composable
private fun ExpandedLayout(container: AppContainer) {
    var selectedFeedId by rememberSaveable { mutableStateOf<Int?>(null) }
    var selectedGroupId by rememberSaveable { mutableStateOf<Int?>(null) }
    var selectedArticleId by rememberSaveable { mutableStateOf<Int?>(null) }
    var showStocks by rememberSaveable { mutableStateOf(false) }
    var showSettings by rememberSaveable { mutableStateOf(false) }

    if (showStocks) {
        StockOverlayNavHost(container.stockStore, onClose = { showStocks = false })
        return
    }
    if (showSettings) {
        SettingsOverlayNavHost(container, onClose = { showSettings = false })
        return
    }

    Row(modifier = Modifier.fillMaxSize()) {
        Box(modifier = Modifier.weight(0.28f)) {
            SidebarScreen(
                groupStore = container.groupStore,
                feedStore = container.feedStore,
                articleStore = container.articleStore,
                settingsStore = container.settingsStore,
                onSelectAll = {
                    selectedFeedId = null
                    selectedGroupId = null
                    selectedArticleId = null
                },
                onSelectFeed = { feedId ->
                    selectedFeedId = feedId
                    selectedGroupId = null
                    selectedArticleId = null
                },
                onSelectGroup = { groupId ->
                    selectedGroupId = groupId
                    selectedFeedId = null
                    selectedArticleId = null
                },
                onStockTap = { showStocks = true },
                onSettingsTap = { showSettings = true },
            )
        }
        VerticalDivider()
        Box(modifier = Modifier.weight(0.36f)) {
            ArticleListScreen(
                feedId = selectedFeedId,
                groupId = selectedGroupId,
                articleStore = container.articleStore,
                feedStore = container.feedStore,
                groupStore = container.groupStore,
                stockStore = container.stockStore,
                onArticleSelected = { articleId -> selectedArticleId = articleId },
                onStockTap = { showStocks = true },
            )
        }
        VerticalDivider()
        Box(modifier = Modifier.weight(0.36f)) {
            val articleId = selectedArticleId
            if (articleId != null) {
                ArticleDetailScreen(articleId = articleId, articleStore = container.articleStore)
            } else {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = "記事を選択",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/// Expanded レイアウト用のストック全画面 NavHost（iOS fullScreenCover { StockRootView(isModal: true) } 相当）。
@Composable
private fun StockOverlayNavHost(stockStore: StockStore, onClose: () -> Unit) {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = StockCategoryListRoute) {
        stockGraph(navController, stockStore, onClose = onClose)
    }
}

/// Expanded レイアウト用の設定全画面 NavHost（iOS の SettingsView.sheet 相当を全画面表示に読み替え）。
@Composable
private fun SettingsOverlayNavHost(container: AppContainer, onClose: () -> Unit) {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = SettingsRoute) {
        settingsGraph(navController, container, onClose = onClose)
    }
}
