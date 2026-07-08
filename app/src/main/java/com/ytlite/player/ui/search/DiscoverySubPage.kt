package com.ytlite.player.ui.search

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.DiscoveryType
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.parser.BrowseMoodItem
import com.ytlite.player.data.parser.BrowsePage
import com.ytlite.player.ui.home.VideoFeedItem
import com.ytlite.player.ui.image.rememberYTLiteImageLoader
import com.ytlite.player.ui.library.LibraryImage

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverySubPage(
    type: DiscoveryType,
    page: BrowsePage?,
    isLoading: Boolean,
    error: String?,
    onBack: () -> Unit,
    onVideoClick: (String) -> Unit,
    onMoodClick: (BrowseMoodItem) -> Unit,
    modifier: Modifier = Modifier,
) {
    val title = when (type) {
        DiscoveryType.NEW_RELEASES -> stringResource(R.string.search_new_releases)
        DiscoveryType.CHARTS -> stringResource(R.string.search_charts)
        DiscoveryType.MOODS_AND_GENRES -> stringResource(R.string.search_moods)
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.player_back))
                    }
                },
            )
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                isLoading && page == null -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }
                error != null && page == null -> {
                    Text(
                        text = error,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.align(Alignment.Center),
                    )
                }
                page != null -> {
                    when (type) {
                        DiscoveryType.NEW_RELEASES -> NewReleasesContent(page, onVideoClick)
                        DiscoveryType.CHARTS -> ChartsContent(page, onVideoClick)
                        DiscoveryType.MOODS_AND_GENRES -> MoodsContent(page, onMoodClick)
                    }
                }
            }
        }
    }
}

@Composable
private fun NewReleasesContent(page: BrowsePage, onVideoClick: (String) -> Unit) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        page.featuredVideo?.let { featured ->
            item(key = "featured") {
                FeaturedVideoCard(featured, onVideoClick)
            }
        }
        page.sections.forEach { section ->
            item(key = "section_${section.title}") {
                Text(section.title, style = MaterialTheme.typography.titleMedium)
            }
            item(key = "shelf_${section.title}") {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(section.videos, key = { it.videoId }) { video ->
                        ShelfVideoCard(video, onVideoClick)
                    }
                }
            }
        }
    }
}

@Composable
private fun ChartsContent(page: BrowsePage, onVideoClick: (String) -> Unit) {
    val imageLoader = rememberYTLiteImageLoader()
    LazyColumn(contentPadding = PaddingValues(vertical = 8.dp)) {
        items(page.rankedVideos, key = { it.videoId }) { video ->
            VideoFeedItem(
                video = video,
                imageLoader = imageLoader,
                onClick = { onVideoClick(video.videoId) },
            )
        }
    }
}

@Composable
private fun MoodsContent(
    page: BrowsePage,
    onMoodClick: (BrowseMoodItem) -> Unit,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(page.moodItems, key = { it.browseId }) { mood ->
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(96.dp)
                    .clickable { onMoodClick(mood) },
            ) {
                Row(modifier = Modifier.fillMaxSize()) {
                    Box(
                        modifier = Modifier
                            .size(width = 6.dp, height = 96.dp)
                            .background(Color(mood.accentColorArgb ?: 0xFF6200EE.toInt())),
                    )
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .padding(12.dp),
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(mood.title, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    LibraryImage(
                        model = mood.thumbnailUrl,
                        contentDescription = mood.title,
                        modifier = Modifier
                            .size(96.dp)
                            .clip(RoundedCornerShape(topEnd = 12.dp, bottomEnd = 12.dp)),
                    )
                }
            }
        }
    }
}

@Composable
private fun FeaturedVideoCard(video: VideoItem, onVideoClick: (String) -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onVideoClick(video.videoId) },
    ) {
        Column {
            LibraryImage(
                model = video.thumbnailUrl,
                contentDescription = video.title,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(180.dp),
            )
            Text(
                text = video.title,
                modifier = Modifier.padding(12.dp),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun ShelfVideoCard(video: VideoItem, onVideoClick: (String) -> Unit) {
    Column(
        modifier = Modifier
            .size(width = 160.dp, height = 140.dp)
            .clickable { onVideoClick(video.videoId) },
    ) {
        LibraryImage(
            model = video.thumbnailUrl,
            contentDescription = video.title,
            modifier = Modifier
                .fillMaxWidth()
                .height(90.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        Text(
            text = video.title,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}
