import React, { Component, Children, cloneElement, useEffect, useCallback, useState, useRef } from 'react';
import { View, ViewPropTypes } from 'react-native';
import PropTypes from 'prop-types';
import { pick, isNull } from 'underscore';
import { setNativeEvents, removeNativeEvents,  OT } from './OT';
import { sanitizeSessionEvents, sanitizeSessionOptions, sanitizeSignalData,
   sanitizeCredentials, getConnectionStatus } from './helpers/OTSessionHelper';
import { handleError } from './OTError';
import { logOT, getOtrnErrorEventHandler } from './helpers/OTHelper';
import OTContext from './contexts/OTContext';

const OTSession: () => React$Node = (props) => {
  let [sessionInfo, setSessionInfo] = useState(null);
  let otrnEventHandler = useRef(null);

  let createSession = useCallback((credentials, sessionOptions) => {

    const { apiKey, sessionId, token } = credentials;
    OT.initSession(apiKey, sessionId, sessionOptions);
    OT.connect(sessionId, token, (error) => {
      if (error) {
        otrnEventHandler.current(error);
      } else {
        OT.getSessionInfo(sessionId, (session) => {
          if (!isNull(session)) {
            const sessionInfo = { ...session, connectionStatus: getConnectionStatus(session.connectionStatus)};
            setSessionInfo(sessionInfo);
            logOT({ apiKey, sessionId, action: 'rn_on_connect', proxyUrl: sessionOptions.proxyUrl, connectionId: session.connection.connectionId });
            if (Object.keys(props.signal).length > 0) {
              signal(props.signal);
            }
          }
        });
      }
    });
  })

  let disconnectSession = useCallback(() => {
    OT.disconnectSession(props.sessionId, (disconnectError) => {
      if (disconnectError) {
        otrnEventHandler.current(disconnectError);
      } else {
        const events = sanitizeSessionEvents(props.sessionId, props.eventHandlers);
        removeNativeEvents(events);
      }
    });
  })

  let signal = useCallback((signal) => {
    const signalData = sanitizeSignalData(signal);
    OT.sendSignal(props.sessionId, signalData.signal, signalData.errorHandler);
  })

  useEffect(() => {

    otrnEventHandler.current = getOtrnErrorEventHandler(props.eventHandlers);

    const credentials = pick(props, ['apiKey', 'sessionId', 'token']);

    if (Object.keys(credentials).length === 3) {
      const sessionEvents = sanitizeSessionEvents(credentials.sessionId, props.eventHandlers);
      setNativeEvents(sessionEvents);
    }
    const sessionOptions = sanitizeSessionOptions(props.options);
    createSession(credentials, sessionOptions);

    return disconnectSession;
  }, [])

  useEffect(() => {
    // componentDidUpdate
    const useDefault = (value, defaultValue) => (value === undefined ? defaultValue : value);

    const updateSessionProperty = (key, defaultValue) => {
      const value = useDefault(props[key], defaultValue);
      signal(value);
    };

    updateSessionProperty('signal', {});
  }, [sessionInfo])


  return (
    <OTContext.Provider value={{ sessionId: props.sessionId, sessionInfo: sessionInfo }}>
      <View style={props.style}>
        { props.children }
      </View>
    </OTContext.Provider>
  );
}


OTSession.propTypes = {
  apiKey: PropTypes.string.isRequired,
  sessionId: PropTypes.string.isRequired,
  token: PropTypes.string.isRequired,
  children: PropTypes.oneOfType([
    PropTypes.element,
    PropTypes.arrayOf(PropTypes.element),
  ]),
  style: ViewPropTypes.style,
  eventHandlers: PropTypes.object, // eslint-disable-line react/forbid-prop-types
  options: PropTypes.object, // eslint-disable-line react/forbid-prop-types
  signal: PropTypes.object, // eslint-disable-line react/forbid-prop-types
};

OTSession.defaultProps = {
  eventHandlers: {},
  options: {},
  signal: {},
  style: {
    flex: 1
  },
};

export default OTSession;