package net.piagent.piagent

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.math.BigInteger
import java.security.AlgorithmParameters
import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECFieldFp
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

internal class EnrollmentChannel(private val activity: Activity) {
    private data class EphemeralKey(val privateKey: PrivateKey, val expiresAt: Long)

    private val keyStore by lazy { KeyStore.getInstance("AndroidKeyStore").apply { load(null) } }
    private val curve by lazy {
        AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }
            .getParameterSpec(ECParameterSpec::class.java)
    }
    private val ephemeralKeys = LinkedHashMap<String, EphemeralKey>()
    private val profile by lazy { AtomicFile(File(activity.noBackupFilesDir, "enrollment-profile")) }
    private var wifiResult: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "publicKey" -> result.success(publicKey(identityAlias(call)))
                "sign" -> result.success(sign(identityAlias(call), call.bytes("data")))
                "verify" -> result.success(verify(call.bytes("publicKey"), call.bytes("data"), call.bytes("signature")))
                "ephemeralPublicKey" -> result.success(ephemeralPublicKey(sessionId(call)))
                "discardEphemeral" -> {
                    ephemeralKeys.remove(sessionId(call))
                    result.success(null)
                }
                "decrypt" -> result.success(decrypt(sessionId(call), call))
                "saveProfile" -> {
                    saveProfile(requireNotNull(call.argument<String>("data")))
                    result.success(null)
                }
                "loadProfile" -> result.success(loadProfile())
                "connectWifi" -> connectWifi(
                    requireNotNull(call.argument<String>("ssid")),
                    requireNotNull(call.argument<String>("password")),
                    result,
                )
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("enrollment_failed", "手机安全存储或注册操作失败。", null)
        }
    }

    private fun identityAlias(call: MethodCall): String {
        val alias = requireNotNull(call.argument<String>("alias"))
        require(alias.matches(Regex("[A-Za-z0-9_.-]{1,160}")))
        return "net.piagent.enrollment.identity.$alias"
    }

    private fun sessionId(call: MethodCall): String {
        val session = requireNotNull(call.argument<String>("session"))
        require(session.matches(Regex("[A-Za-z0-9_-]{1,128}")))
        return session
    }

    private fun MethodCall.bytes(key: String): ByteArray = requireNotNull(argument<ByteArray>(key))

    private fun publicKey(alias: String): ByteArray {
        val existing = keyStore.getCertificate(alias)?.publicKey
        if (existing != null) return rawPublicKey(existing as ECPublicKey)
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        generator.initialize(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .build(),
        )
        return rawPublicKey(generator.generateKeyPair().public as ECPublicKey)
    }

    private fun sign(alias: String, data: ByteArray): ByteArray {
        val privateKey = keyStore.getKey(alias, null) as PrivateKey
        return Signature.getInstance("SHA256withECDSA").run {
            initSign(privateKey)
            update(data)
            sign()
        }
    }

    private fun verify(publicKey: ByteArray, data: ByteArray, signature: ByteArray): Boolean {
        return try {
            Signature.getInstance("SHA256withECDSA").run {
                initVerify(parsePublicKey(publicKey))
                update(data)
                verify(signature)
            }
        } catch (_: GeneralSecurityException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    private fun rawPublicKey(publicKey: ECPublicKey): ByteArray {
        fun fieldBytes(value: BigInteger): ByteArray {
            val bytes = value.toByteArray()
            val result = ByteArray(32)
            val count = minOf(bytes.size, result.size)
            bytes.copyInto(result, result.size - count, bytes.size - count)
            return result
        }
        val point = publicKey.w
        return byteArrayOf(4) + fieldBytes(point.affineX) + fieldBytes(point.affineY)
    }

    private fun parsePublicKey(raw: ByteArray): ECPublicKey {
        require(raw.size == 65 && raw[0] == 4.toByte())
        val x = BigInteger(1, raw.copyOfRange(1, 33))
        val y = BigInteger(1, raw.copyOfRange(33, 65))
        val field = curve.curve
        val p = (field.field as ECFieldFp).p
        require(x < p && y < p)
        require((y * y).mod(p) == (x.pow(3) + field.a * x + field.b).mod(p))
        val spec = ECPublicKeySpec(ECPoint(x, y), curve)
        return KeyFactory.getInstance("EC").generatePublic(spec) as ECPublicKey
    }

    private fun ephemeralPublicKey(session: String): ByteArray {
        val now = SystemClock.elapsedRealtime()
        ephemeralKeys.entries.removeAll { it.value.expiresAt <= now }
        require(session !in ephemeralKeys && ephemeralKeys.size < 4)
        val generator = KeyPairGenerator.getInstance("EC")
        generator.initialize(ECGenParameterSpec("secp256r1"))
        val pair = generator.generateKeyPair()
        ephemeralKeys[session] = EphemeralKey(pair.private, now + 120_000)
        return rawPublicKey(pair.public as ECPublicKey)
    }

    private fun decrypt(session: String, call: MethodCall): ByteArray {
        val ephemeral = requireNotNull(ephemeralKeys.remove(session))
        require(ephemeral.expiresAt > SystemClock.elapsedRealtime())
        val salt = call.bytes("salt")
        val sealed = call.bytes("sealed")
        require(salt.size == 32 && sealed.size >= 28)
        val agreement = KeyAgreement.getInstance("ECDH")
        agreement.init(ephemeral.privateKey)
        agreement.doPhase(parsePublicKey(call.bytes("serverPublicKey")), true)
        val secret = agreement.generateSecret()
        val mac = Mac.getInstance("HmacSHA256")
        val prk = try {
            mac.init(SecretKeySpec(salt, "HmacSHA256"))
            mac.doFinal(secret)
        } finally {
            secret.fill(0)
        }
        val key = try {
            mac.init(SecretKeySpec(prk, "HmacSHA256"))
            mac.doFinal("piagent/enrollment/response/v1".encodeToByteArray() + byteArrayOf(1))
        } finally {
            prk.fill(0)
        }
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, sealed, 0, 12))
            cipher.updateAAD(call.bytes("associatedData"))
            cipher.doFinal(sealed, 12, sealed.size - 12)
        } finally {
            key.fill(0)
        }
    }

    private fun saveProfile(data: String) {
        val key = profileKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val plaintext = data.encodeToByteArray()
        val encrypted = try {
            cipher.iv + cipher.doFinal(plaintext)
        } finally {
            plaintext.fill(0)
        }
        val output = profile.startWrite()
        try {
            output.write(encrypted)
            profile.finishWrite(output)
        } catch (failure: Exception) {
            profile.failWrite(output)
            throw failure
        }
    }

    private fun loadProfile(): String? {
        val encrypted = try {
            profile.readFully()
        } catch (_: FileNotFoundException) {
            return null
        }
        require(encrypted.size >= 28)
        val key = keyStore.getKey(PROFILE_KEY, null) as SecretKey
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, encrypted, 0, 12))
        val plaintext = cipher.doFinal(encrypted, 12, encrypted.size - 12)
        return try {
            plaintext.decodeToString(throwOnInvalidSequence = true)
        } finally {
            plaintext.fill(0)
        }
    }

    private fun profileKey(): SecretKey {
        val existing = keyStore.getKey(PROFILE_KEY, null) as SecretKey?
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(PROFILE_KEY, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private fun connectWifi(ssid: String, password: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.error("wifi_unsupported", "保存树莓派热点需要 Android 11 或更高版本。", null)
            return
        }
        if (wifiResult != null) {
            result.error("wifi_in_progress", "等待系统热点授权完成。", null)
            return
        }
        val network = WifiNetworkSuggestion.Builder().setSsid(ssid).setWpa2Passphrase(password).build()
        val intent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS)
            .putParcelableArrayListExtra(Settings.EXTRA_WIFI_NETWORK_LIST, arrayListOf(network))
        wifiResult = result
        try {
            activity.startActivityForResult(intent, WIFI_REQUEST)
        } catch (_: ActivityNotFoundException) {
            wifiResult = null
            result.error("wifi_unsupported", "系统没有提供保存热点的设置页面。", null)
        } catch (failure: Exception) {
            wifiResult = null
            throw failure
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != WIFI_REQUEST || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val pending = wifiResult ?: return
        wifiResult = null
        val status = data?.getIntegerArrayListExtra(Settings.EXTRA_WIFI_NETWORK_RESULT_LIST)?.singleOrNull()
        pending.success(
            resultCode == Activity.RESULT_OK &&
                (status == Settings.ADD_WIFI_RESULT_SUCCESS || status == Settings.ADD_WIFI_RESULT_ALREADY_EXISTS),
        )
    }

    private companion object {
        const val PROFILE_KEY = "net.piagent.enrollment.profile.v1"
        const val WIFI_REQUEST = 2042
    }
}
