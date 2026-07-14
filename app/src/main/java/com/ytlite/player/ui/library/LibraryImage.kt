package com.ytlite.player.ui.library

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import coil.compose.AsyncImage
import com.ytlite.player.ui.image.rememberYTLiteImageLoader
import com.ytlite.player.ui.image.thumbnailRequest

@Composable
fun LibraryImage(
    model: Any?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
) {
    val context = LocalContext.current
    val imageLoader = rememberYTLiteImageLoader()
    AsyncImage(
        model = when (model) {
            is String -> thumbnailRequest(context, model)
            else -> model
        },
        contentDescription = contentDescription,
        imageLoader = imageLoader,
        modifier = modifier,
        contentScale = contentScale,
    )
}
