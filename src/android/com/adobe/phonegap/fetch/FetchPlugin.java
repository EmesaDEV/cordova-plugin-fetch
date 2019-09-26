package com.adobe.phonegap.fetch;

import android.util.Log;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.Headers;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.OkHttpClient.Builder;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.util.Iterator;
import java.util.List;
import java.util.concurrent.TimeUnit;

public class FetchPlugin extends CordovaPlugin {

    public static final String LOG_TAG = "FetchPlugin";
    private static CallbackContext callbackContext;


    // We use 60 seconds timeout for XMLHttpRequests (also for the live connection)
    private final OkHttpClient mClient = new OkHttpClient.Builder()
        .followRedirects(false)
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build();

    public static final MediaType MEDIA_TYPE_MARKDOWN = MediaType.parse("application/x-www-form-urlencoded; charset=utf-8");

    @Override
    public boolean execute(final String action, final JSONArray data, final CallbackContext callbackContext) {

        if (action.equals("fetch")) {

            try {
                String method = data.getString(0);
                Log.v(LOG_TAG, "execute: method = " + method.toString());

                String urlString = data.getString(1);
                Log.v(LOG_TAG, "execute: urlString = " + urlString.toString());

                String postBody = data.getString(2);
                Log.v(LOG_TAG, "execute: postBody = " + postBody.toString());

                JSONObject headers = data.getJSONObject(3);
                if (headers.has("map") && headers.getJSONObject("map") != null) {
                    headers = headers.getJSONObject("map");
                }

                Log.v(LOG_TAG, "execute: headers = " + headers.toString());

                Request.Builder requestBuilder = new Request.Builder();

                // method + postBody
                if (postBody != null && !postBody.equals("null")) {
                    if (headers.has("content-type") && headers.getJSONArray("content-type") != null) {
                        String theContentType = "";
                        JSONArray contentTypes = headers.getJSONArray("content-type");

                        for (int i = 0; i < contentTypes.length(); i++) {
                            theContentType += contentTypes.getString(i);
                            if (i != contentTypes.length() - 1) {
                                theContentType += "; ";
                            }
                        }

                        MediaType postMediaType = MediaType.parse(theContentType);
                        requestBuilder.post(RequestBody.create(postMediaType, postBody.toString()));
                    } else {
                        requestBuilder.post(RequestBody.create(MEDIA_TYPE_MARKDOWN, postBody.toString()));
                    }
                } else {
                    requestBuilder.method(method, null);
                }

                // url
                requestBuilder.url(urlString);

                // headers
                if (headers != null && headers.names() != null && headers.names().length() > 0) {
                    for (int i = 0; i < headers.names().length(); i++) {

                        String headerName = headers.names().getString(i);
                        JSONArray headerValues = headers.getJSONArray(headers.names().getString(i));

                        if (headerValues.length() > 0) {
                            String headerValue = headerValues.getString(0);
                            Log.v(LOG_TAG, "key = " + headerName + " value = " + headerValue);
                            requestBuilder.addHeader(headerName, headerValue);
                        }
                    }
                }

                Request request = requestBuilder.build();
                mClient.newCall(request).enqueue(new Callback() {
                    @Override
                    public void onFailure(Call call, IOException throwable) {
                        throwable.printStackTrace();
                        callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, throwable.getMessage()));
                    }

                    @Override
                    public void onResponse(Call call, Response response) throws IOException {
                        JSONObject result = new JSONObject();
                        try {
                            Headers responseHeaders = response.headers();
                            JSONObject allHeaders = new JSONObject();
                            for (int i = 0; i < responseHeaders.size(); i++) {
                                String name = responseHeaders.name(i);
                                List<String> values = responseHeaders.values(name);
                                if (name.equalsIgnoreCase("Set-Cookie")) {
                                    allHeaders.put(name, new JSONArray(values));
                                } else {
                                    allHeaders.put(name, values.get(0));
                                }
                            }
                            result.put("headers", allHeaders);
                            result.put("statusText", response.body().string());
                            result.put("status", response.code());
                            result.put("url", response.request().url().toString());
                        } catch (Exception e) {
                            e.printStackTrace();
                        }

                        // Log.v(LOG_TAG, "HTTP code: " + response.code());
                        // Log.v(LOG_TAG, "returning: " + result.toString());

                        callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, result));
                    }
                });

            } catch (JSONException e) {
                Log.e(LOG_TAG, "execute: Got JSON Exception " + e.getMessage());
                callbackContext.error(e.getMessage());
            }

        } else {
            Log.e(LOG_TAG, "Invalid action : " + action);
            callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.INVALID_ACTION));
            return false;
        }

        return true;
    }
}
