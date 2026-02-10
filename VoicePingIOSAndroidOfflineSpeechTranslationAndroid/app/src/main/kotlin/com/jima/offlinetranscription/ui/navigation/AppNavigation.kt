package com.voiceping.offlinetranscription.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.voiceping.offlinetranscription.data.AppDatabase
import com.voiceping.offlinetranscription.data.TranscriptionEntity
import com.voiceping.offlinetranscription.service.WhisperEngine
import com.voiceping.offlinetranscription.ui.history.HistoryDetailScreen
import com.voiceping.offlinetranscription.ui.history.HistoryScreen
import com.voiceping.offlinetranscription.ui.history.HistoryViewModel
import com.voiceping.offlinetranscription.ui.transcription.TranscriptionScreen
import com.voiceping.offlinetranscription.ui.transcription.TranscriptionViewModel
import androidx.compose.ui.platform.LocalContext

object Routes {
    const val MAIN = "main"
    const val TRANSCRIBE = "transcribe"
    const val HISTORY = "history"
    const val HISTORY_DETAIL = "history/{recordId}"
}

@Composable
fun AppNavigation(
    engine: WhisperEngine,
    database: AppDatabase
) {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = Routes.MAIN) {
        composable(Routes.MAIN) {
            MainTabScreen(
                engine = engine,
                database = database
            )
        }

        composable(
            Routes.HISTORY_DETAIL,
            arguments = listOf(navArgument("recordId") { type = NavType.StringType })
        ) { backStackEntry ->
            val recordId = backStackEntry.arguments?.getString("recordId") ?: return@composable
            var record by remember { mutableStateOf<TranscriptionEntity?>(null) }
            LaunchedEffect(recordId) {
                record = database.transcriptionDao().getById(recordId)
            }
            record?.let {
                HistoryDetailScreen(record = it, onBack = { navController.popBackStack() })
            }
        }
    }
}

@Composable
fun MainTabScreen(
    engine: WhisperEngine,
    database: AppDatabase
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("Transcribe" to Icons.Filled.Mic, "History" to Icons.Filled.History)

    // Shared navigation for history detail
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { index, (title, icon) ->
                    NavigationBarItem(
                        icon = { Icon(icon, contentDescription = title) },
                        label = { Text(title) },
                        selected = selectedTab == index,
                        onClick = { selectedTab = index }
                    )
                }
            }
        }
    ) { paddingValues ->
        val context = LocalContext.current
        when (selectedTab) {
            0 -> {
                val viewModel = remember { TranscriptionViewModel(engine, database, context.filesDir) }
                Box(modifier = Modifier.padding(bottom = paddingValues.calculateBottomPadding())) {
                    TranscriptionScreen(viewModel = viewModel)
                }
            }
            1 -> {
                val viewModel = remember { HistoryViewModel(database, context.filesDir) }
                NavHost(
                    navController = navController,
                    startDestination = "history_list",
                    modifier = Modifier.padding(paddingValues)
                ) {
                    composable("history_list") {
                        HistoryScreen(
                            viewModel = viewModel,
                            onRecordClick = { id ->
                                navController.navigate("history_detail/$id")
                            }
                        )
                    }
                    composable(
                        "history_detail/{recordId}",
                        arguments = listOf(navArgument("recordId") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val recordId = backStackEntry.arguments?.getString("recordId") ?: return@composable
                        var record by remember { mutableStateOf<TranscriptionEntity?>(null) }
                        LaunchedEffect(recordId) {
                            record = database.transcriptionDao().getById(recordId)
                        }
                        record?.let {
                            HistoryDetailScreen(record = it, onBack = { navController.popBackStack() })
                        }
                    }
                }
            }
        }
    }
}
