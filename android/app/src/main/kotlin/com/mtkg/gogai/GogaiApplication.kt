package com.mtkg.gogai

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.mtkg.gogai.di.AppContainer

class GogaiApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)

        // iOS の scenePhase == .background 相当: バックグラウンド移行時にシークレット表示をリセットする
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStop(owner: LifecycleOwner) {
                container.groupStore.resetSecretVisibility()
            }
        })
    }
}
