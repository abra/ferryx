"use strict";

// The active panel keeps the chosen 2 px frame in every variant.
window.ferryxPrototypeStudy = {
  defaultVariant: "plain",
  activePane: "left",
  comparisonVariants: ["plain", "fill", "pill"],
  comparisonIntro: "Рамка выделяет активную панель. У вкладок убрана синяя линия; выбранная вкладка различается оформлением. Клик или Tab переключает панели во всех вариантах.",
  variants: {
    underline: {
      letter: "",
      name: "Было",
      description: "Предыдущее оформление: рамка панели и синяя линия под выбранной вкладкой.",
      focusVariant: "frame",
      tabStyle: "underline",
    },
    plain: {
      letter: "A",
      name: "Просто без линии",
      description: "Привычные вкладки. Выбранная читается по тексту и светлой поверхности.",
      focusVariant: "frame",
      tabStyle: "plain",
    },
    fill: {
      letter: "B",
      name: "Спокойная заливка",
      description: "Выбранная вкладка выделяется нейтральным фоном без подчёркивания.",
      focusVariant: "frame",
      tabStyle: "fill",
    },
    pill: {
      letter: "C",
      name: "Скруглённая плашка",
      description: "Выбранная вкладка — небольшая плашка с нейтральным контуром.",
      focusVariant: "frame",
      tabStyle: "pill",
    },
  },
};
