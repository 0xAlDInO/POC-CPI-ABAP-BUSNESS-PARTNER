import com.sap.gateway.ip.core.customdev.util.Message

def Message processData(Message message) {
    // Generate or fetch unique DataStore entry ID
    def bpId = message.getProperty("BusinessPartnerID") ?: "BP_TEMP_" + System.currentTimeMillis()
    def dataStoreName = "BP_Relations_Backup_DS"

    message.setHeader("SAP_DataStoreName", dataStoreName)
    message.setHeader("SAP_DataStoreEntryId", bpId)

    // Flag to indicate backup success
    message.setProperty("DataStoreBackupCompleted", "true")

    return message
}
