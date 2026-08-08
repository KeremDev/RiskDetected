package com.riskdetectedan.feature.capture

import android.Manifest
import android.content.pm.PackageManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * CameraX capture screen (2026-08-08 visual pass, Faz H of the core-flow redesign) — no System
 * Photo Picker fallback wired yet (master §15.3), same pre-existing gap as before this pass.
 *
 * Not a port of any iOS file — iOS has no dedicated camera-view source (capture is folded into
 * `HomeView.swift`/`ImagePicker.swift`, per the core-flow survey), so this camera chrome (top
 * scrim+back button, circular shutter, permission screen) is a from-scratch Android design
 * following the app's existing dark/onyx/white token language, not a simplification of anything.
 * Standard camera-UI convention (dark gradient scrims for legibility over a live feed, circular
 * shutter button) rather than a custom illustration.
 */
@Composable
fun CaptureScreen(onPhotoCaptured: (File) -> Unit = {}, onBack: (() -> Unit)? = null) {
    val context = LocalContext.current
    val colors = RdTheme.colors
    val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    val coroutineScope = rememberCoroutineScope()

    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val permissionLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { granted -> hasCameraPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    if (!hasCameraPermission) {
        Column(
            modifier = Modifier.fillMaxSize().background(colors.paper).padding(RdSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (onBack != null) {
                IconButton(onClick = onBack, modifier = Modifier.size(40.dp)) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Geri", tint = colors.onyx)
                }
            }
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        modifier = Modifier.size(88.dp).clip(CircleShape).background(colors.fog),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.CameraAlt, contentDescription = null, tint = colors.slate, modifier = Modifier.size(36.dp))
                    }
                    Spacer(Modifier.height(RdSpacing.sm))
                    Text("Kameraya erişim gerekiyor", style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(RdSpacing.sm))
                    Text(
                        "Tehlikeleri fotoğraflayıp analiz edebilmek için kamera iznine ihtiyacımız var.",
                        style = RdFontStyle.Footnote.toTextStyle(),
                        color = colors.slate,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(RdSpacing.sm))
                    RdPrimaryButton(
                        text = "İzin ver",
                        onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) },
                        style = RdButtonStyle.Onyx,
                        showArrow = false,
                    )
                }
            }
        }
        return
    }

    var imageCapture by remember { mutableStateOf<ImageCapture?>(null) }
    var isCapturing by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                val previewView = PreviewView(ctx)
                val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
                cameraProviderFuture.addListener({
                    val cameraProvider = cameraProviderFuture.get()
                    val preview = Preview.Builder().build().also {
                        it.surfaceProvider = previewView.surfaceProvider
                    }
                    val capture = ImageCapture.Builder().build()
                    imageCapture = capture
                    try {
                        cameraProvider.unbindAll()
                        cameraProvider.bindToLifecycle(
                            lifecycleOwner,
                            CameraSelector.DEFAULT_BACK_CAMERA,
                            preview,
                            capture,
                        )
                    } catch (_: Exception) {
                        // Camera bind failures surface as a black preview — acceptable for this
                        // skeleton; real error UX lands with the rest of the capture flow.
                    }
                }, ContextCompat.getMainExecutor(ctx))
                previewView
            },
        )

        // Top scrim + back button — standard camera-UI legibility pattern over a live feed.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp)
                .align(Alignment.TopCenter)
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent))),
        ) {
            if (onBack != null) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .padding(top = 44.dp, start = RdSpacing.md)
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.35f)),
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Geri", tint = Color.White)
                }
            }
        }

        // Bottom scrim + circular shutter button.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(180.dp)
                .align(Alignment.BottomCenter)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.55f)))),
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = RdSpacing.xxl)
                .size(76.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .clip(CircleShape)
                    .background(if (isCapturing) Color.White.copy(alpha = 0.5f) else Color.White)
                    .clickable(enabled = !isCapturing) {
                        val capture = imageCapture ?: return@clickable
                        isCapturing = true
                        val fileName = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US)
                            .format(System.currentTimeMillis())
                        val outputFile = File(context.cacheDir, "rd_capture_$fileName.jpg")
                        val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()
                        capture.takePicture(
                            outputOptions,
                            ContextCompat.getMainExecutor(context),
                            object : ImageCapture.OnImageSavedCallback {
                                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                                    isCapturing = false
                                    coroutineScope.launch { onPhotoCaptured(outputFile) }
                                }

                                override fun onError(exception: ImageCaptureException) {
                                    isCapturing = false
                                }
                            },
                        )
                    },
                contentAlignment = Alignment.Center,
            ) {
                if (isCapturing) {
                    CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(28.dp), strokeWidth = 3.dp)
                } else {
                    Icon(Icons.Filled.PhotoCamera, contentDescription = "Fotoğraf çek", tint = Color.Black, modifier = Modifier.size(28.dp))
                }
            }
        }
    }
}

/** Referenced so FileProvider's manifest entry has a real symbol to point at once wired. */
internal fun capturedPhotoUri(context: android.content.Context, file: File) =
    FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
