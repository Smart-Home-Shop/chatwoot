<script setup>
import { ref, watch, onUnmounted } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  conversationId: {
    type: Number,
    required: true,
  },
});

const SPAM_LABEL = 'spam';
const UNDO_WINDOW_SECONDS = 10;

const store = useStore();
const { t } = useI18n();

// The conversation being flagged, captured at click time so switching threads mid-countdown flags the right one
const pendingConversationId = ref(null);
const secondsLeft = ref(UNDO_WINDOW_SECONDS);

const markAsSpam = async conversationId => {
  try {
    const labels =
      store.getters['conversationLabels/getConversationLabels'](conversationId);
    await store.dispatch('conversationLabels/update', {
      conversationId,
      labels: [...new Set([...labels, SPAM_LABEL])],
    });
    await store.dispatch('muteConversation', conversationId);
    useAlert(t('CONVERSATION.HEADER.FLAG_SPAM.SUCCESS'));
  } catch {
    useAlert(t('CONVERSATION.HEADER.FLAG_SPAM.ERROR'));
  }
};

const { pause, resume } = useIntervalFn(
  () => {
    secondsLeft.value -= 1;
    // eslint-disable-next-line no-use-before-define
    if (secondsLeft.value <= 0) confirm();
  },
  1000,
  { immediate: false }
);

const confirm = () => {
  if (!pendingConversationId.value) return;
  pause();
  const conversationId = pendingConversationId.value;
  pendingConversationId.value = null;
  markAsSpam(conversationId);
};

const startFlag = () => {
  pendingConversationId.value = props.conversationId;
  secondsLeft.value = UNDO_WINDOW_SECONDS;
  resume();
};

const undo = () => {
  pause();
  pendingConversationId.value = null;
};

// Leaving the thread mid-countdown applies the flag, as letting the timer run out would
watch(() => props.conversationId, confirm);
onUnmounted(confirm);
</script>

<template>
  <div
    v-if="pendingConversationId"
    class="flex items-center gap-1 ps-2 rounded-lg bg-n-ruby-2 outline outline-1 outline-n-ruby-5"
  >
    <span class="text-xs text-n-ruby-11 whitespace-nowrap tabular-nums">
      {{
        t('CONVERSATION.HEADER.FLAG_SPAM.COUNTDOWN', { seconds: secondsLeft })
      }}
    </span>
    <Button
      size="sm"
      variant="ghost"
      color="slate"
      :label="t('CONVERSATION.HEADER.FLAG_SPAM.UNDO')"
      @click="undo"
    />
    <Button
      size="sm"
      color="ruby"
      :label="t('CONVERSATION.HEADER.FLAG_SPAM.CONFIRM')"
      @click="confirm"
    />
  </div>
  <Button
    v-else
    v-tooltip="t('CONVERSATION.HEADER.FLAG_SPAM.TOOLTIP')"
    size="sm"
    variant="faded"
    color="ruby"
    icon="i-lucide-shield-alert"
    :label="t('CONVERSATION.HEADER.FLAG_SPAM.BUTTON')"
    @click="startFlag"
  />
</template>
