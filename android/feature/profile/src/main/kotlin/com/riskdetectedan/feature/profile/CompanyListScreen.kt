package com.riskdetectedan.feature.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.company.CompanyDraft
import com.riskdetectedan.core.designsystem.RdSpacing

/** Port of the company list + add form from App/Services/CompanyService.swift's contract
 * (no dedicated iOS view file was read for layout — CompanyPickerSheet.swift exists but this is
 * the management surface, not the analysis-time picker; kept minimal/functional). */
@Composable
fun CompanyListScreen(viewModel: CompanyViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    val saveError by viewModel.saveError.collectAsState()
    var name by remember { mutableStateOf("") }

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Firmalar")

        when (val current = state) {
            is CompanyListUiState.Loading -> CircularProgressIndicator()
            is CompanyListUiState.Failed -> Text(current.message)
            is CompanyListUiState.Loaded -> LazyColumn(modifier = Modifier.padding(top = RdSpacing.sm)) {
                items(current.companies) { company ->
                    ListItem(
                        headlineContent = { Text(company.name) },
                        supportingContent = { Text(company.hazardClass.title) },
                    )
                }
            }
        }

        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("Yeni firma adı") },
            modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.md),
        )
        Button(
            onClick = {
                viewModel.addCompany(CompanyDraft(name = name))
                name = ""
            },
            enabled = name.isNotBlank(),
            modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm),
        ) {
            Text("Firma ekle")
        }
        saveError?.let { Text(it) }
    }
}
