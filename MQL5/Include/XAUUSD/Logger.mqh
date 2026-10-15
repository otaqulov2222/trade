#ifndef XAU_LOGGER_MQH
#define XAU_LOGGER_MQH

#include "Config.mqh"

ENUM_XAU_LOG_LEVEL g_xau_log_level = XAU_LOG_INFO;

void XauSetLogLevel(const ENUM_XAU_LOG_LEVEL level)
{
   g_xau_log_level = level;
}

string XauLogLevelName(const ENUM_XAU_LOG_LEVEL level)
{
   if(level == XAU_LOG_ERROR) return "ERROR";
   if(level == XAU_LOG_WARN)  return "WARN";
   return "INFO";
}

void XauLog(const ENUM_XAU_LOG_LEVEL level, const string component, const string message)
{
   if((int)level > (int)g_xau_log_level)
      return;
   Print("[XAUUSD][" + XAU_PHASE_NAME + "][" + XauLogLevelName(level) + "][" + component + "] " + message);
}

void XauLogMultiline(const ENUM_XAU_LOG_LEVEL level, const string component, const string message)
{
   string lines[];
   const ushort separator = 10;
   const int count = StringSplit(message, separator, lines);
   if(count <= 0)
   {
      XauLog(level, component, message);
      return;
   }
   for(int i = 0; i < count; ++i)
   {
      if(StringLen(lines[i]) == 0)
         continue;
      XauLog(level, component, lines[i]);
   }
}

string XauDeinitReasonName(const int reason)
{
   if(reason == REASON_PROGRAM)     return "program";
   if(reason == REASON_REMOVE)      return "remove";
   if(reason == REASON_RECOMPILE)   return "recompile";
   if(reason == REASON_CHARTCHANGE) return "chart_change";
   if(reason == REASON_CHARTCLOSE)  return "chart_close";
   if(reason == REASON_PARAMETERS)  return "parameters";
   if(reason == REASON_ACCOUNT)     return "account";
   if(reason == REASON_TEMPLATE)    return "template";
   if(reason == REASON_INITFAILED)  return "init_failed";
   if(reason == REASON_CLOSE)       return "terminal_close";
   return "other";
}

#endif
