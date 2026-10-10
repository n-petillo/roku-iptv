package com.npetillo.fedsmokertv

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import okhttp3.OkHttpClient

class FedSmokerApp : Application(), ImageLoaderFactory {
    // channel logos: same User-Agent as the API, no crossfade
    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .okHttpClient {
            OkHttpClient.Builder()
                .addInterceptor { chain -> chain.proceed(chain.request().newBuilder().header("User-Agent", USER_AGENT).build()) }
                .build()
        }
        .crossfade(false)
        .respectCacheHeaders(false)
        .build()
}
