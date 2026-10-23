package com.example.road_companion

import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.util.UUID

/**
 * Gestor del servidor GATT local para el Tripper Pod de Royal Enfield.
 * 
 * Basado en la implementación de referencia verificada en hardware real (WazeTripper / MCUXpresso):
 * El Tripper Pod es bidireccional. Además de conectar como cliente GATT al servicio del Pod,
 * el teléfono hospeda un servidor GATT local con el mismo UUID de servicio y característica.
 * El Tripper Pod escribe sus respuestas (ACK, confirmaciones, estado) a través de este servidor.
 */
object TripperGattServerManager {
    val SERVICE_UUID: UUID = UUID.fromString("01FF0100-BA5E-F4EE-5CA1-EB1E5E4B1CE0")
    val CHAR_UUID: UUID = UUID.fromString("01FF0101-BA5E-F4EE-5CA1-EB1E5E4B1CE0")

    private var gattServer: BluetoothGattServer? = null

    var onDataReceivedListener: ((bytesHex: String, deviceAddress: String) -> Unit)? = null
    var onConnectionStateListener: ((state: String, deviceAddress: String) -> Unit)? = null

    fun isServerRunning(): Boolean = gattServer != null

    @SuppressLint("MissingPermission")
    fun startGattServer(context: Context): Map<String, Any> {
        if (gattServer != null) {
            return mapOf(
                "success" to true,
                "message" to "GATT Server local ya se encuentra activo.",
                "running" to true
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                return mapOf(
                    "success" to false,
                    "message" to "Permiso BLUETOOTH_CONNECT no concedido en Android 12+.",
                    "running" to false
                )
            }
        }

        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: return mapOf(
                "success" to false,
                "message" to "BluetoothManager no disponible en el sistema.",
                "running" to false
            )

        val callback = object : BluetoothGattServerCallback() {
            @SuppressLint("MissingPermission")
            override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
                val stateStr = if (newState == BluetoothProfile.STATE_CONNECTED) "connected" else "disconnected"
                onConnectionStateListener?.invoke(stateStr, device.address)
            }

            @SuppressLint("MissingPermission")
            override fun onCharacteristicWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                characteristic: BluetoothGattCharacteristic,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray?
            ) {
                val bytes = value ?: ByteArray(0)
                val hexString = bytes.joinToString("") { "%02X".format(it) }
                onDataReceivedListener?.invoke(hexString, device.address)

                if (responseNeeded && gattServer != null) {
                    try {
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, ByteArray(0))
                    } catch (e: Exception) {
                        // ignore
                    }
                }
            }

            @SuppressLint("MissingPermission")
            override fun onCharacteristicReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                characteristic: BluetoothGattCharacteristic
            ) {
                if (gattServer == null) return
                try {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, ByteArray(0))
                } catch (e: Exception) {
                    // ignore
                }
            }
        }

        return try {
            val server = bluetoothManager.openGattServer(context, callback)
            if (server == null) {
                return mapOf(
                    "success" to false,
                    "message" to "openGattServer retornó null (adaptador Bluetooth inactivo o fallo nativo).",
                    "running" to false
                )
            }

            gattServer = server
            val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            val characteristic = BluetoothGattCharacteristic(
                CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )
            service.addCharacteristic(characteristic)
            val serviceAdded = server.addService(service)

            mapOf(
                "success" to serviceAdded,
                "message" to if (serviceAdded) {
                    "Servidor GATT local iniciado con éxito (Servicio 01FF0100 / Característica 01FF0101)."
                } else {
                    "Fallo al agregar el servicio GATT local 01FF0100."
                },
                "running" to serviceAdded
            )
        } catch (e: Exception) {
            mapOf(
                "success" to false,
                "message" to "Excepción al iniciar GATT Server: ${e.localizedMessage}",
                "running" to false
            )
        }
    }

    @SuppressLint("MissingPermission")
    fun stopGattServer() {
        try {
            gattServer?.close()
        } catch (e: Exception) {
            // ignore
        }
        gattServer = null
    }
}
