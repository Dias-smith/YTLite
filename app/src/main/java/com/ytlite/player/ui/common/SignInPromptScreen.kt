package com.ytlite.player.ui.common

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.ytlite.player.R

private val IllustrationGrey = Color(0xFFE0E0E0)
private val IllustrationGreyDark = Color(0xFFBDBDBD)
private val YoutubeBlue = Color(0xFF065FD4)

@Composable
fun SignInPromptScreen(
    title: String,
    description: String,
    illustration: @Composable () -> Unit,
    onSignInClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        illustration()
        Spacer(modifier = Modifier.height(32.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(24.dp))
        Button(
            onClick = onSignInClick,
            shape = RoundedCornerShape(50),
            colors = ButtonDefaults.buttonColors(containerColor = YoutubeBlue),
        ) {
            Text(
                text = stringResource(R.string.sign_in),
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
    }
}

@Composable
fun SubscriptionsIllustration(
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier.size(width = 120.dp, height = 100.dp)) {
        val cardWidth = size.width * 0.72f
        val cardHeight = size.height * 0.55f
        val corner = CornerRadius(12f, 12f)

        drawRoundRect(
            color = IllustrationGreyDark,
            topLeft = Offset(size.width * 0.18f, size.height * 0.02f),
            size = Size(cardWidth, cardHeight * 0.85f),
            cornerRadius = corner,
        )
        drawRoundRect(
            color = IllustrationGrey,
            topLeft = Offset(size.width * 0.1f, size.height * 0.12f),
            size = Size(cardWidth, cardHeight * 0.9f),
            cornerRadius = corner,
        )
        val frontLeft = Offset(size.width * 0.02f, size.height * 0.24f)
        val frontSize = Size(cardWidth, cardHeight)
        drawRoundRect(
            color = IllustrationGrey,
            topLeft = frontLeft,
            size = frontSize,
            cornerRadius = corner,
        )

        val playCenter = Offset(
            frontLeft.x + frontSize.width / 2f,
            frontLeft.y + frontSize.height / 2f,
        )
        val triangleSize = frontSize.width * 0.18f
        val playPath = Path().apply {
            moveTo(playCenter.x - triangleSize * 0.35f, playCenter.y - triangleSize * 0.5f)
            lineTo(playCenter.x - triangleSize * 0.35f, playCenter.y + triangleSize * 0.5f)
            lineTo(playCenter.x + triangleSize * 0.55f, playCenter.y)
            close()
        }
        drawPath(playPath, color = Color.White)
    }
}

@Composable
fun LibraryIllustration(
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier.size(96.dp)) {
        val folderWidth = size.width * 0.85f
        val folderHeight = size.height * 0.7f
        val left = (size.width - folderWidth) / 2f
        val top = size.height * 0.2f

        drawRoundRect(
            color = IllustrationGrey,
            topLeft = Offset(left, top + folderHeight * 0.08f),
            size = Size(folderWidth, folderHeight),
            cornerRadius = CornerRadius(8f, 8f),
        )
        drawRoundRect(
            color = IllustrationGreyDark,
            topLeft = Offset(left, top),
            size = Size(folderWidth * 0.42f, folderHeight * 0.22f),
            cornerRadius = CornerRadius(6f, 6f),
        )
        drawRoundRect(
            color = IllustrationGrey,
            topLeft = Offset(left, top + folderHeight * 0.12f),
            size = Size(folderWidth, folderHeight * 0.88f),
            cornerRadius = CornerRadius(8f, 8f),
            style = Stroke(width = 2f),
        )
    }
}
