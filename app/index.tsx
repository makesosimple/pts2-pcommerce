import * as Linking from "expo-linking";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  BackHandler,
  Platform,
  RefreshControl,
  StatusBar,
  StyleSheet,
  View,
} from "react-native";
import { WebView } from "react-native-webview";

const TARGET_URL = "https://loreal-pts.makesosimple.com/login";

export default function Home() {
  const webRef = useRef<WebView>(null);
  const [canGoBack, setCanGoBack] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [key, setKey] = useState(0);

  useEffect(() => {
    const sub = BackHandler.addEventListener("hardwareBackPress", () => {
      if (canGoBack && webRef.current) {
        webRef.current.goBack();
        return true;
      }
      return false;
    });
    return () => sub.remove();
  }, [canGoBack]);

  const onShouldStartLoadWithRequest = useCallback((req: any) => {
    try {
      const u = new URL(req.url);
      const isOurHost = u.hostname === "loreal-pts.makesosimple.com";
      if (!isOurHost && req.mainDocumentURL === req.url) {
        Linking.openURL(req.url);
        return false;
      }
    } catch {}
    return true;
  }, []);

  const onNavStateChange = useCallback((state: any) => {
    setCanGoBack(state.canGoBack);
  }, []);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    setKey((k) => k + 1);
  }, []);

  const onLoadEnd = useCallback(() => {
    if (refreshing) setRefreshing(false);
  }, [refreshing]);

  // Make the page itself paint the full-screen gradient (exact stops) and fill viewport.
  const injectedCSS = `
    (function(){
      try {
        const css = \`
          html, body, #app { height: 100% !important; min-height: 100vh !important; margin: 0 !important; }
          body { background: linear-gradient(90deg, #c7a150, #c7bfa1 35%, #c7a150) !important; background-attachment: fixed !important; }
          .bg-overlay { display: none !important; background: transparent !important; }
        \`;
        const s = document.createElement('style'); s.type='text/css'; s.appendChild(document.createTextNode(css));
        document.head.appendChild(s);
        const ov = document.querySelector('.bg-overlay'); if (ov) { ov.style.display='none'; ov.style.background='transparent'; }
      } catch(e) {}
      true;
    })();
  `;

  return (
    <View style={styles.root}>
      <StatusBar
        barStyle={Platform.OS === "ios" ? "dark-content" : "light-content"}
      />
      <WebView
        key={key}
        ref={webRef}
        source={{ uri: TARGET_URL }}
        originWhitelist={["*"]}
        onNavigationStateChange={onNavStateChange}
        onShouldStartLoadWithRequest={onShouldStartLoadWithRequest}
        onLoadEnd={onLoadEnd}
        javaScriptEnabled
        domStorageEnabled
        // important bits so the webpage fills the whole screen:
        automaticallyAdjustContentInsets={false}
        contentInsetAdjustmentBehavior="never"
        bounces={false}
        // let the web page be the only background source
        style={styles.webview}
        injectedJavaScriptBeforeContentLoaded={injectedCSS}
        injectedJavaScript={injectedCSS}
        pullToRefreshEnabled={Platform.OS === "android"}
        {...(Platform.OS === "ios"
          ? {
              refreshControl: (
                <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
              ),
            }
          : {})}
        renderLoading={() => (
          <View style={styles.loader}>
            <ActivityIndicator />
          </View>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#00000000" }, // fully transparent; nothing behind
  webview: { flex: 1, backgroundColor: "transparent" },
  loader: {
    ...StyleSheet.absoluteFillObject,
    alignItems: "center",
    justifyContent: "center",
  },
});
