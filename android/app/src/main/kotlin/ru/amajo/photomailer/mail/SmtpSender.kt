package ru.amajo.photomailer.mail

import java.io.File
import java.nio.charset.StandardCharsets
import java.util.Date
import java.util.Properties
import jakarta.activation.DataHandler
import jakarta.activation.FileDataSource
import jakarta.mail.Message
import jakarta.mail.Part
import jakarta.mail.Session
import jakarta.mail.internet.InternetAddress
import jakarta.mail.internet.MimeBodyPart
import jakarta.mail.internet.MimeMessage
import jakarta.mail.internet.MimeMultipart
import jakarta.mail.internet.MimeUtility

data class OutgoingAttachment(
    val file: File,
    val displayName: String,
    val mimeType: String,
)

enum class SmtpAuthMode {
    OAUTH2,
    APP_PASSWORD,
}

class SmtpSender(
    private val senderEmail: String,
    private val smtpHost: String,
    private val smtpPort: Int,
    private val oauthToken: String? = null,
    private val appPassword: String? = null,
    private val useStartTls: Boolean = false,
) {
    fun send(
        recipientEmail: String,
        subject: String,
        bodyText: String,
        attachments: List<OutgoingAttachment>,
        authMode: SmtpAuthMode = defaultAuthMode(),
    ) {
        val session = createSession(authMode)
        val message = MimeMessage(session).apply {
            setFrom(InternetAddress(senderEmail))
            setRecipients(Message.RecipientType.TO, InternetAddress.parse(recipientEmail, false))
            this.subject = subject
            sentDate = Date()
            setContent(buildMultipart(bodyText = bodyText, attachments = attachments))
        }
        val transport = session.getTransport("smtp")
        try {
            connect(transport = transport, authMode = authMode)
            transport.sendMessage(message, message.allRecipients)
        } finally {
            transport.close()
        }
    }

    fun verifyConnection(
        authMode: SmtpAuthMode = defaultAuthMode(),
    ) {
        val session = createSession(authMode)
        val transport = session.getTransport("smtp")
        try {
            connect(transport = transport, authMode = authMode)
        } finally {
            transport.close()
        }
    }

    private fun buildMultipart(
        bodyText: String,
        attachments: List<OutgoingAttachment>,
    ): MimeMultipart {
        val multipart = MimeMultipart()

        val textPart = MimeBodyPart().apply {
            setText(bodyText, StandardCharsets.UTF_8.name())
        }
        multipart.addBodyPart(textPart)

        for (attachment in attachments) {
            val bodyPart = MimeBodyPart().apply {
                dataHandler = DataHandler(FileDataSource(attachment.file))
                fileName = MimeUtility.encodeText(
                    attachment.displayName,
                    StandardCharsets.UTF_8.name(),
                    null,
                )
                disposition = Part.ATTACHMENT
                setHeader("Content-Type", attachment.mimeType)
            }
            multipart.addBodyPart(bodyPart)
        }

        return multipart
    }

    private fun connect(
        transport: jakarta.mail.Transport,
        authMode: SmtpAuthMode,
    ) {
        when (authMode) {
            SmtpAuthMode.OAUTH2 -> {
                val token = oauthToken?.trim().orEmpty()
                require(token.isNotBlank()) { "OAuth token is missing for SMTP connection" }
                transport.connect(smtpHost, senderEmail, token)
            }

            SmtpAuthMode.APP_PASSWORD -> {
                val password = appPassword?.trim().orEmpty()
                require(password.isNotBlank()) { "App password is missing for SMTP connection" }
                transport.connect(smtpHost, senderEmail, password)
            }
        }
    }

    private fun createSession(authMode: SmtpAuthMode): Session {
        val props = Properties().apply {
            put("mail.smtp.host", smtpHost)
            put("mail.smtp.port", smtpPort.toString())
            put("mail.smtp.auth", "true")
            put("mail.smtp.ssl.enable", if (useStartTls) "false" else "true")
            put("mail.smtp.starttls.enable", if (useStartTls) "true" else "false")
            put("mail.smtp.connectiontimeout", "30000")
            put("mail.smtp.timeout", "120000")
            put("mail.smtp.writetimeout", "120000")
            put("mail.smtp.ssl.protocols", "TLSv1.2 TLSv1.3")
            put("mail.smtp.ssl.checkserveridentity", "true")
            when (authMode) {
                SmtpAuthMode.OAUTH2 -> {
                    put("mail.smtp.auth.mechanisms", "XOAUTH2")
                    put("mail.smtp.auth.login.disable", "true")
                    put("mail.smtp.auth.plain.disable", "true")
                }

                SmtpAuthMode.APP_PASSWORD -> {
                    put("mail.smtp.auth.login.disable", "false")
                    put("mail.smtp.auth.plain.disable", "false")
                    put("mail.smtp.auth.mechanisms", "LOGIN PLAIN")
                    put("mail.smtp.auth.xoauth2.disable", "true")
                }
            }
        }
        return Session.getInstance(props)
    }

    private fun defaultAuthMode(): SmtpAuthMode {
        return if (!oauthToken.isNullOrBlank()) {
            SmtpAuthMode.OAUTH2
        } else {
            SmtpAuthMode.APP_PASSWORD
        }
    }
}
