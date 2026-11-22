package com.petrixon.vpn

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var vpnEngineChannel: VpnEngineChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        vpnEngineChannel = VpnEngineChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (vpnEngineChannel?.onActivityResult(requestCode, resultCode) == true) {
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (vpnEngineChannel?.onRequestPermissionsResult(requestCode) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
