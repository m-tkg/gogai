package com.mtkg.gogai.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import com.mtkg.gogai.GogaiApplication
import com.mtkg.gogai.ui.ai.LocalAppContainer
import com.mtkg.gogai.ui.theme.GogaiTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as GogaiApplication).container
        setContent {
            // AI 機能を持つ画面（ArticleDetailScreen 等）が NavHost の引数を経由せず
            // AppContainer を参照できるようにする（ui/ai/LocalAppContainer.kt を参照）。
            CompositionLocalProvider(LocalAppContainer provides container) {
                GogaiTheme {
                    Surface(modifier = Modifier.fillMaxSize()) {
                        GogaiRoot(container)
                    }
                }
            }
        }
    }
}
